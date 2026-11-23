"""
SSM-driven ECS blue/green deployer.

Triggered by EventBridge when an image-tag SSM parameter is created/updated:

  SSM /<project>/<env>/<service>/image-tag  --(Parameter Store Change)-->  this Lambda
    1. read the new tag, verify the image exists in ECR
    2. register a new task-definition revision (latest revision, image swapped)
    3. start an AWS CodeDeploy blue/green deployment with an inline AppSpec

Writing the same tag again ("refresh") redeploys the latest task definition,
e.g. to roll out environment changes made by Terraform.
"""

import json
import logging
import os
import re

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

ssm = boto3.client("ssm")
ecr = boto3.client("ecr")
ecs = boto3.client("ecs")
codedeploy = boto3.client("codedeploy")

# { "<ssm parameter name>": { service, family, container, port, repository, repository_url,
#                             application, deployment_group } }
CONFIG = json.loads(os.environ["DEPLOY_CONFIG"])

TAG_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")

# Fields of DescribeTaskDefinition that RegisterTaskDefinition accepts.
REGISTER_FIELDS = (
    "family", "taskRoleArn", "executionRoleArn", "networkMode", "containerDefinitions",
    "volumes", "placementConstraints", "requiresCompatibilities", "cpu", "memory",
    "pidMode", "ipcMode", "proxyConfiguration", "inferenceAccelerators",
    "ephemeralStorage", "runtimePlatform",
)


def handler(event, _context):
    detail = event.get("detail", {})
    param_name = detail.get("name")
    log.info("event: %s %s", detail.get("operation"), param_name)

    cfg = CONFIG.get(param_name)
    if cfg is None:
        raise ValueError(f"no deploy configuration for parameter {param_name!r}")

    param = ssm.get_parameter(Name=param_name)["Parameter"]
    tag, version = param["Value"].strip(), param["Version"]
    if not TAG_PATTERN.match(tag) or tag == "latest":
        raise ValueError(f"refusing to deploy invalid or mutable tag {tag!r}")

    # Fail fast (before touching ECS) if the image was never pushed.
    ecr.describe_images(repositoryName=cfg["repository"], imageIds=[{"imageTag": tag}])
    image = f"{cfg['repository_url']}:{tag}"

    # Base the new revision on the latest one, so Terraform-managed settings
    # (env vars, secrets, CPU/memory) are carried over and only the image changes.
    current = ecs.describe_task_definition(taskDefinition=cfg["family"], include=["TAGS"])
    td = current["taskDefinition"]
    new_td = {k: td[k] for k in REGISTER_FIELDS if td.get(k)}

    found = False
    for container in new_td["containerDefinitions"]:
        if container["name"] == cfg["container"]:
            container["image"] = image
            found = True
    if not found:
        raise ValueError(f"container {cfg['container']!r} not in task definition {cfg['family']}")

    if current.get("tags"):
        new_td["tags"] = current["tags"]

    registered = ecs.register_task_definition(**new_td)["taskDefinition"]
    task_def_arn = registered["taskDefinitionArn"]
    log.info("registered %s with image %s", task_def_arn, image)

    appspec = {
        "version": "0.0",
        "Resources": [{
            "TargetService": {
                "Type": "AWS::ECS::Service",
                "Properties": {
                    "TaskDefinition": task_def_arn,
                    "LoadBalancerInfo": {
                        "ContainerName": cfg["container"],
                        "ContainerPort": cfg["port"],
                    },
                },
            }
        }],
    }

    deployment = codedeploy.create_deployment(
        applicationName=cfg["application"],
        deploymentGroupName=cfg["deployment_group"],
        description=f"{cfg['service']} -> {tag} (ssm {param_name} v{version})",
        revision={
            "revisionType": "AppSpecContent",
            "appSpecContent": {"content": json.dumps(appspec)},
        },
    )
    deployment_id = deployment["deploymentId"]
    log.info("started CodeDeploy deployment %s for %s", deployment_id, cfg["service"])

    return {"deploymentId": deployment_id, "taskDefinition": task_def_arn, "image": image}
