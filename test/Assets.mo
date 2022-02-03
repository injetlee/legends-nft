import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal";

import Admins "../src/Admins";
import Assets "../src/Assets";
import Types "../src/Assets/types";

func createAsset(name : Text, tags : [Text]) : Types.Record = {
    asset = {
        contentType = "raw";
        payload     = [Blob.fromArray([0x00])];
    };
    meta = {
        tags        = tags;
        filename    = name # ".data";
        name        = name;
        description = "";
    };
};

let admin = Principal.fromText("2ibo7-dia");
let state : Types.State = {
    assets  = [
        createAsset("asset0", ["border", "raw", "data"]),
        createAsset("asset1", ["border", "tag0", "tag1"]),
        createAsset("asset2", ["backs", "tag2"]),
        createAsset("asset3", ["preview", "tag0", "tag1", "tag3"]),
    ];
    _Admins = Admins.Admins({ admins = [admin] });
};
let a = Assets.Assets(state);

assert(a._flattenPayload([
    Blob.fromArray([0x00]),
    Blob.fromArray([0x01, 0x02]),
    Blob.fromArray([0x03]),
]) == Blob.fromArray([0x00, 0x01, 0x02, 0x03]));

switch (a._findTag("tag1")) {
    case (?r) assert(r.meta.name == "asset1");
    case (_)  assert(false);
};

// No such asset with tag 4.
switch (a._findTag("tag4")) {
    case (?r) assert(false);
    case (_)  {};
};

switch (a._findTags(["tag0", "tag1"])) {
    case (?r) assert(r.meta.name == "asset1");
    case (_)  assert(false);
};

switch (a._findTags(["tag2"])) {
    case (?r) assert(r.meta.name == "asset2");
    case (_)  assert(false);
};

// No asset with both tag 0 and 2.
switch (a._findTags(["tag0", "tag2"])) {
    case (?r) assert(false);
    case (_)  {};
};

assert(a._findAllTag("tag0").size() == 2);

assert(a._getAllCardBorders().size() == 2);
assert(a._getAllCardBacks().size() == 1);
switch (a._getPreview()) {
    case (?r) assert(r.meta.name == "asset3");
    case (_)  assert(false);
};

switch (a.getAssetByName("asset0.data")) {
    case (?r) {}; // OK
    case (_)  assert(false);
};

switch (a.getAssetByName("asset4.data")) {
    case (?r) assert(false);
    case (_)  {}; // OK
};

assert(a.getManifest().size() == 4);

// TODO: file upload, finalize, clear and purge.

Debug.print("✅ Assets.mo");
