import os

envs = ['development', 'nonproduction', 'production']
base = '/Users/james/Workspace/gh/infrastructure/vitruvian/pulumi_ts-example-foundation/5-app-infra/business_unit_1/'

for env in envs:
    path = os.path.join(base, env, 'index.ts')
    with open(path, 'r') as f:
        content = f.read()
    
    # Fix the literal ${env} issue
    if '`projects-bu1-${env}`' in content:
        content = content.replace(
            '`projects-bu1-${env}`',
            f'"{f"projects-bu1-{env}"}"'
        )
    
    with open(path, 'w') as f:
        f.write(content)
print("done")
