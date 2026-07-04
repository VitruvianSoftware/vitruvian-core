import re
import sys

def rewrite_test_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # We want to replace the TestConfigDefaults function with the mocked version.
    # The mocks implementation needs to be added to the file if it's not there.
    if "type mocks int" not in content:
        mocks_impl = """
import (
\t"os"
\t"testing"

\t"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
\t"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
\t"github.com/stretchr/testify/assert"
)

type mocks int

func (mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
\treturn args.Name + "_id", args.Inputs, nil
}
func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
\treturn args.Args, nil
}
"""
        # Replace the imports
        content = re.sub(r'import \(\n\t"testing"\n\n\t"github\.com/stretchr/testify/assert"\n\)', mocks_impl, content)

    # Now we need to rewrite the test body.
    # We'll just read the file manually and do replace_file_content for each since they are different.
    
if __name__ == "__main__":
    rewrite_test_file(sys.argv[1])
