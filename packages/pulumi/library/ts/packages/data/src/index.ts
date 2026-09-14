import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface DataPlatformArgs {
  /** Project ID. */
  projectId: pulumi.Input<string>;
  /** Location/Region. */
  location: pulumi.Input<string>;
  /** Raw dataset ID (defaults to "raw_data"). */
  rawDatasetId?: string;
  /** Curated dataset ID (defaults to "curated_data"). */
  curatedDatasetId?: string;
}

export class DataPlatform extends pulumi.ComponentResource {
  public readonly rawDataset: gcp.bigquery.Dataset;
  public readonly curatedDataset: gcp.bigquery.Dataset;

  constructor(
    name: string,
    args: DataPlatformArgs,
    opts?: pulumi.ComponentResourceOptions,
  ) {
    super("foundation:modules:DataPlatform", name, args, opts);

    const rawId = args.rawDatasetId ?? "raw_data";
    const curatedId = args.curatedDatasetId ?? "curated_data";

    this.rawDataset = new gcp.bigquery.Dataset(
      `${name}-raw`,
      {
        datasetId: rawId,
        project: args.projectId,
        location: args.location,
      },
      { parent: this },
    );

    this.curatedDataset = new gcp.bigquery.Dataset(
      `${name}-curated`,
      {
        datasetId: curatedId,
        project: args.projectId,
        location: args.location,
      },
      { parent: this },
    );

    this.registerOutputs({
      rawDatasetId: this.rawDataset.datasetId,
      curatedDatasetId: this.curatedDataset.datasetId,
    });
  }
}
