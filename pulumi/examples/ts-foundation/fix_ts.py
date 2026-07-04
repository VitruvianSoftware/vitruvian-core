import os

envs = ['development', 'nonproduction', 'production']
base = '/Users/james/Workspace/gh/infrastructure/vitruvian/pulumi_ts-example-foundation/5-app-infra/business_unit_1/'

for env in envs:
    path = os.path.join(base, env, 'index.ts')
    with open(path, 'r') as f:
        content = f.read()
    
    # Check if we need to fix tee-image-reference
    if 'pulumi.interpolate`${region}-docker.pkg.dev/${cloudbuildProjectId}/tf-runners/confidential_space_image:latest`,' in content:
        content = content.replace(
            'pulumi.interpolate`${region}-docker.pkg.dev/${cloudbuildProjectId}/tf-runners/confidential_space_image:latest`,',
            'pulumi.interpolate`${region}-docker.pkg.dev/${cloudbuildProjectId}/tf-runners/confidential_space_image:latest` as any,'
        )
    
    with open(path, 'w') as f:
        f.write(content)
print("done")
