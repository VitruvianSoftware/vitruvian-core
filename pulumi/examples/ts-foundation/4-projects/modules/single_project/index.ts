import * as pulumi from "@pulumi/pulumi";
import { ProjectFactory, ProjectFactoryArgs } from "@vitruviansoftware/foundation-project-factory";

export class SingleProject extends pulumi.ComponentResource {
    public readonly projectId: pulumi.Output<string>;
    public readonly projectNumber: pulumi.Output<string>;
    public readonly serviceAccountEmail: pulumi.Output<string>;

    constructor(name: string, args: ProjectFactoryArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:SingleProject", name, args, opts);

        const project = new ProjectFactory(name, args, { parent: this });

        this.projectId = project.projectId;
        this.projectNumber = project.projectNumber;
        this.serviceAccountEmail = project.serviceAccountEmail;

        this.registerOutputs({
            projectId: this.projectId,
            projectNumber: this.projectNumber,
            serviceAccountEmail: this.serviceAccountEmail,
        });
    }
}
