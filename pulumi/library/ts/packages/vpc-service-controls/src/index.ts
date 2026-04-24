/**
 * VPC Service Controls Module
 * Mirrors: pulumi-library/go/pkg/vpc_sc/vpc_sc.go
 * Upstream: terraform-google-modules/vpc-service-controls
 *
 * Creates Access Context Manager access levels and a service perimeter
 * that protects GCP API resources within a defined boundary. Supports
 * both enforced and dry-run (audit-only) modes.
 *
 * Resources created:
 *   - Access Level (enforced member list)
 *   - Access Level (dry-run member list)
 *   - Service Perimeter with enforced + dry-run spec
 */

import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

/** Default restricted services matching the Go library's GetDefaultRestrictedServices(). */
export const DEFAULT_RESTRICTED_SERVICES: string[] = [
    "accessapproval.googleapis.com",
    "adsdatahub.googleapis.com",
    "aiplatform.googleapis.com",
    "alloydb.googleapis.com",
    "analyticshub.googleapis.com",
    "apigee.googleapis.com",
    "apigeeconnect.googleapis.com",
    "artifactregistry.googleapis.com",
    "assuredworkloads.googleapis.com",
    "automl.googleapis.com",
    "baremetalsolution.googleapis.com",
    "batch.googleapis.com",
    "bigquery.googleapis.com",
    "bigquerydatapolicy.googleapis.com",
    "bigquerydatatransfer.googleapis.com",
    "bigquerymigration.googleapis.com",
    "bigqueryreservation.googleapis.com",
    "bigtable.googleapis.com",
    "binaryauthorization.googleapis.com",
    "cloud.googleapis.com",
    "cloudasset.googleapis.com",
    "cloudbuild.googleapis.com",
    "clouddebugger.googleapis.com",
    "clouddeploy.googleapis.com",
    "clouderrorreporting.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudprofiler.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudsearch.googleapis.com",
    "cloudtrace.googleapis.com",
    "composer.googleapis.com",
    "compute.googleapis.com",
    "confidentialcomputing.googleapis.com",
    "connectgateway.googleapis.com",
    "contactcenterinsights.googleapis.com",
    "container.googleapis.com",
    "containeranalysis.googleapis.com",
    "containerfilesystem.googleapis.com",
    "containerregistry.googleapis.com",
    "containerthreatdetection.googleapis.com",
    "datacatalog.googleapis.com",
    "dataflow.googleapis.com",
    "datafusion.googleapis.com",
    "datamigration.googleapis.com",
    "dataplex.googleapis.com",
    "dataproc.googleapis.com",
    "datastream.googleapis.com",
    "dialogflow.googleapis.com",
    "dlp.googleapis.com",
    "dns.googleapis.com",
    "documentai.googleapis.com",
    "domains.googleapis.com",
    "eventarc.googleapis.com",
    "file.googleapis.com",
    "firebaseappcheck.googleapis.com",
    "firebaserules.googleapis.com",
    "firestore.googleapis.com",
    "gameservices.googleapis.com",
    "gkebackup.googleapis.com",
    "gkeconnect.googleapis.com",
    "gkehub.googleapis.com",
    "healthcare.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "iaptunnel.googleapis.com",
    "ids.googleapis.com",
    "integrations.googleapis.com",
    "kmsinventory.googleapis.com",
    "krmapihosting.googleapis.com",
    "language.googleapis.com",
    "lifesciences.googleapis.com",
    "logging.googleapis.com",
    "managedidentities.googleapis.com",
    "memcache.googleapis.com",
    "meshca.googleapis.com",
    "meshconfig.googleapis.com",
    "metastore.googleapis.com",
    "ml.googleapis.com",
    "monitoring.googleapis.com",
    "networkconnectivity.googleapis.com",
    "networkmanagement.googleapis.com",
    "networksecurity.googleapis.com",
    "networkservices.googleapis.com",
    "notebooks.googleapis.com",
    "opsconfigmonitoring.googleapis.com",
    "orgpolicy.googleapis.com",
    "osconfig.googleapis.com",
    "oslogin.googleapis.com",
    "privateca.googleapis.com",
    "pubsub.googleapis.com",
    "pubsublite.googleapis.com",
    "recaptchaenterprise.googleapis.com",
    "recommender.googleapis.com",
    "redis.googleapis.com",
    "retail.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "servicecontrol.googleapis.com",
    "servicedirectory.googleapis.com",
    "spanner.googleapis.com",
    "speakerid.googleapis.com",
    "speech.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "storagetransfer.googleapis.com",
    "sts.googleapis.com",
    "texttospeech.googleapis.com",
    "timeseriesinsights.googleapis.com",
    "tpu.googleapis.com",
    "trafficdirector.googleapis.com",
    "transcoder.googleapis.com",
    "translate.googleapis.com",
    "videointelligence.googleapis.com",
    "vision.googleapis.com",
    "visionai.googleapis.com",
    "vmmigration.googleapis.com",
    "vpcaccess.googleapis.com",
    "webrisk.googleapis.com",
    "workflows.googleapis.com",
    "workstations.googleapis.com",
];

export interface VpcServiceControlsArgs {
    /** Access Context Manager policy ID. Can be bare ID or "accessPolicies/<id>" format. */
    policyId: pulumi.Input<string>;
    /** Prefix for naming access levels and perimeters (e.g., env code). */
    prefix: string;
    /** Members for the enforced access level (e.g., "user:x@y.com", "serviceAccount:..."). */
    members: string[];
    /** Members for the dry-run access level. Defaults to `members` if empty. */
    membersDryRun?: string[];
    /** Project numbers to include in the perimeter (without "projects/" prefix). */
    projectNumbers: pulumi.Input<string>[];
    /** GCP services to restrict within the perimeter. Defaults to DEFAULT_RESTRICTED_SERVICES. */
    restrictedServices?: string[];
    /** GCP services to restrict in dry-run mode. Defaults to restrictedServices if empty. */
    restrictedServicesDryRun?: string[];
    /** Whether to enforce the perimeter (true) or use dry-run only (false). */
    enforce: boolean;
    /** Ingress policies for the enforced perimeter. */
    ingressPolicies?: gcp.types.input.accesscontextmanager.ServicePerimeterStatusIngressPolicy[];
    /** Egress policies for the enforced perimeter. */
    egressPolicies?: gcp.types.input.accesscontextmanager.ServicePerimeterStatusEgressPolicy[];
    /** Ingress policies for the dry-run spec. */
    ingressPoliciesDryRun?: gcp.types.input.accesscontextmanager.ServicePerimeterSpecIngressPolicy[];
    /** Egress policies for the dry-run spec. */
    egressPoliciesDryRun?: gcp.types.input.accesscontextmanager.ServicePerimeterSpecEgressPolicy[];
}

/**
 * Normalizes a policy ID input to "accessPolicies/<id>" format.
 */
function normalizePolicyId(policyId: pulumi.Input<string>): pulumi.Output<string> {
    return pulumi.output(policyId).apply(pid => {
        const parts = pid.split("/");
        if (parts.length > 1 && parts[0] === "accessPolicies") {
            return pid;
        }
        return `accessPolicies/${parts[parts.length - 1]}`;
    });
}

export class VpcServiceControls extends pulumi.ComponentResource {
    public readonly accessLevel: gcp.accesscontextmanager.AccessLevel;
    public readonly accessLevelDryRun: gcp.accesscontextmanager.AccessLevel;
    public readonly perimeter: gcp.accesscontextmanager.ServicePerimeter;

    constructor(name: string, args: VpcServiceControlsArgs, opts?: pulumi.ComponentResourceOptions) {
        super("foundation:modules:VpcServiceControls", name, args, opts);

        const normalizedPolicy = normalizePolicyId(args.policyId);

        // ====================================================================
        // 1. Access Level (enforced)
        // Mirrors: google_access_context_manager_access_level "access_level"
        // ====================================================================
        const alName = pulumi.output(args.policyId).apply(pid => {
            const parts = pid.split("/");
            const id = parts[parts.length - 1];
            return `accessPolicies/${id}/accessLevels/alp_${args.prefix}_members`;
        });

        this.accessLevel = new gcp.accesscontextmanager.AccessLevel(`${name}-al`, {
            parent: normalizedPolicy,
            name: alName,
            title: `${args.prefix} Access Level`,
            basic: {
                conditions: [{
                    members: args.members,
                }],
            },
        }, { parent: this });

        // ====================================================================
        // 2. Access Level (dry-run)
        // ====================================================================
        const membersDryRun = args.membersDryRun && args.membersDryRun.length > 0
            ? args.membersDryRun
            : args.members;

        const alDryRunName = pulumi.output(args.policyId).apply(pid => {
            const parts = pid.split("/");
            const id = parts[parts.length - 1];
            return `accessPolicies/${id}/accessLevels/alp_${args.prefix}_members_dry_run`;
        });

        this.accessLevelDryRun = new gcp.accesscontextmanager.AccessLevel(`${name}-al-dry`, {
            parent: normalizedPolicy,
            name: alDryRunName,
            title: `${args.prefix} Access Level (Dry Run)`,
            basic: {
                conditions: [{
                    members: membersDryRun,
                }],
            },
        }, { parent: this });

        // ====================================================================
        // 3. Service Perimeter
        // ====================================================================
        const resources = pulumi.all(args.projectNumbers).apply(nums => nums.map(p => `projects/${p}`));
        const restrictedServices = args.restrictedServices && args.restrictedServices.length > 0
            ? args.restrictedServices
            : DEFAULT_RESTRICTED_SERVICES;
        const restrictedServicesDryRun = args.restrictedServicesDryRun && args.restrictedServicesDryRun.length > 0
            ? args.restrictedServicesDryRun
            : restrictedServices;

        const perimName = pulumi.output(args.policyId).apply(pid => {
            const parts = pid.split("/");
            const id = parts[parts.length - 1];
            return `accessPolicies/${id}/servicePerimeters/sp_${args.prefix}_default_perimeter`;
        });

        // Build enforced status (only when enforce=true)
        const status: gcp.types.input.accesscontextmanager.ServicePerimeterStatus | undefined =
            args.enforce
                ? {
                      resources,
                      accessLevels: [this.accessLevel.name],
                      restrictedServices,
                      vpcAccessibleServices: {
                          enableRestriction: true,
                          allowedServices: ["RESTRICTED-SERVICES"],
                      },
                      ingressPolicies: args.ingressPolicies,
                      egressPolicies: args.egressPolicies,
                  }
                : undefined;

        // Dry-run spec (always present)
        const spec: gcp.types.input.accesscontextmanager.ServicePerimeterSpec = {
            resources,
            accessLevels: [this.accessLevelDryRun.name],
            restrictedServices: restrictedServicesDryRun,
            vpcAccessibleServices: {
                enableRestriction: true,
                allowedServices: ["RESTRICTED-SERVICES"],
            },
            ingressPolicies: args.ingressPoliciesDryRun,
            egressPolicies: args.egressPoliciesDryRun,
        };

        this.perimeter = new gcp.accesscontextmanager.ServicePerimeter(`${name}-perim`, {
            parent: normalizedPolicy,
            name: perimName,
            title: `${args.prefix} Default Perimeter`,
            perimeterType: "PERIMETER_TYPE_REGULAR",
            status,
            spec,
            useExplicitDryRunSpec: true,
        }, { parent: this });

        this.registerOutputs({
            accessLevelId: this.accessLevel.id,
            accessLevelDryRunId: this.accessLevelDryRun.id,
            perimeterId: this.perimeter.id,
        });
    }
}
