import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const scheme = readFileSync(
    "AmgiFeatures/Sources/ReviewFeature/CardAssetScheme.swift",
    "utf8",
);
const paths = readFileSync(
    "Sources/AmgiCardWeb/CardAssetPath.swift",
    "utf8",
);

assert.match(
    paths,
    /static let cardBaseURL = URL\(string: "amgi-asset:\/\/card\/"\)!/,
    "card documents retain their non-file-serving origin",
);
assert.match(
    paths,
    /static let mediaBaseURL = URL\(string: "amgi-asset:\/\/media\/"\)!/,
    "relative template fetches continue to resolve against collection media",
);
assert.doesNotMatch(
    scheme,
    /"Access-Control-Allow-Origin": "\*"/,
    "collection media must never be readable from arbitrary web origins",
);
assert.match(
    scheme,
    /static func accessControlAllowOrigin\(for request: URLRequest\) -> String\?/,
    "the CORS decision must be an independently testable request policy",
);
assert.match(
    scheme,
    /request\.mainDocumentURL/,
    "the unforgeable main-document URL must bind access to the card document",
);
assert.match(
    scheme,
    /origin == "null"/,
    "WebKit may serialize a custom-scheme card origin as null",
);
assert.match(
    scheme,
    /CardAssetPath\.resolve\(url: url, mediaRoot: mediaRoot, bundleRoot: bundleRoot\)/,
    "CORS must not bypass the existing media/assets host and traversal allowlist",
);

console.log("card asset fetch contract: PASS");
