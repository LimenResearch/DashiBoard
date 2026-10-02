import { describe, it, expect } from "vitest";
import { issueFindings } from "./findings";
import type { ProbeIssue } from "./stores";

const issue = (over: Partial<ProbeIssue>): ProbeIssue => ({
  pointer: "/nodes/0/card",
  reason: "through",
  severity: "error",
  found: null,
  allowed: null,
  missing: [],
  related: [],
  message: "",
  ...over,
});

describe("issues the server writes a sentence for", () => {
  // Some of the server's checks describe the document rather than a schema keyword, and their
  // `message` is the whole finding. Anything else is a validator failure, whose message names a
  // JSON Schema keyword and would read as noise next to a control.
  it("keeps the sentence for a refused through chain", () => {
    const found = issueFindings([
      issue({
        reason: "through",
        found: ["TEMP_a"],
        allowed: ["TEMP"],
        message: "Node `r` does not read TEMP_a; it reads TEMP",
      }),
    ]);
    expect(found).toEqual([
      { message: "Node `r` does not read TEMP_a; it reads TEMP", pointer: "/nodes/0/card" },
    ]);
  });

  it("keeps the sentence for the others", () => {
    for (const reason of ["empty", "unproduced", "products"]) {
      const found = issueFindings([issue({ reason, message: `about ${reason}` })]);
      expect(found[0].message, reason).toBe(`about ${reason}`);
    }
  });

  // A validator failure with nothing more specific still names its keyword, so the author can
  // tell "not one of these" from "wrong type" without the server writing prose for each.
  it("falls back to the keyword for a schema failure", () => {
    const found = issueFindings([issue({ reason: "type", message: "ignored" })]);
    expect(found[0].message).toBe("not accepted (type)");
  });
});
