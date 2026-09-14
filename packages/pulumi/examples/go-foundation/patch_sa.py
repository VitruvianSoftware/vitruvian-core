import re

with open("0-bootstrap/sa.go", "r") as f:
    text = f.read()


def patch(text, start_str):
    idx = 0
    while True:
        idx = text.find(start_str, idx)
        if idx == -1:
            break
        # find the opening brace for Args
        args_idx = text.find("{", idx)
        if args_idx == -1:
            break
        # find the matching closing brace
        depth = 1
        curr = args_idx + 1
        while depth > 0 and curr < len(text):
            if text[curr] == "{":
                depth += 1
            elif text[curr] == "}":
                depth -= 1
            curr += 1

        if text[curr : curr + 1] == ")":
            text = text[:curr] + ", dependsOnGroups" + text[curr:]
        idx = curr
    return text


prefixes = [
    "iam.NewOrganizationIAMMember",
    "iam.NewBillingIAMMember",
    "iam.NewServiceAccountIAMMember",
    "iam.NewOrganizationIAMBinding",
    "iam.NewFolderIAMBinding",
    "parentiammember.NewParentIamMember",
    "parentiamremoverole.NewParentIamRemoveRole",
    "storage.NewBucketIAMMember",
]

for p in prefixes:
    text = patch(text, p)

with open("0-bootstrap/sa.go", "w") as f:
    f.write(text)
