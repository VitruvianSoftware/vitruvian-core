/**
 * Local module: centralized-logging
 * Orchestrates log sinks + destinations for the 1-org stage.
 * Wraps @vitruviansoftware/foundation-centralized-logging library.
 *
 * Mirrors: terraform-example-foundation/1-org/modules/centralized-logging
 */

// This local module re-exports the library component. The actual
// orchestration logic (sink creation per destination type, IAM bindings)
// lives in the CentralizedLogging library. This module exists to maintain
// structural parity with the Terraform foundation's modules/ directory.
export {
  CentralizedLogging,
  CentralizedLoggingArgs,
} from "@vitruviansoftware/foundation-centralized-logging";
