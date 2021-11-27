// 3rd Party Imports

import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Ext "mo:ext/Ext";
import Float "mo:base/Float";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Principal "mo:base/Principal";
import Text "mo:base/Text";

// Project Imports

import AssetTypes "../Assets/types";
import Stoic "../Integrations/Stoic";

// Module Imports

import Types "types";


module {

    public class HttpHandler (state : Types.State) {


        ////////////////////////
        // Internals / Utils //
        //////////////////////


        // Attempts to parse a nat from a path string.
        private func natFromText (
            text : Text
        ) : ?Nat {
            var match : ?Nat = null;
            for (i in Iter.range(0, state.supply - 1)) {
                if (Nat.toText(i) == text) {
                    match := ?i;
                };
            };
            match;
        };


        // Returns a 404 if given token isn't minted yet.
        private func mintedOr404 (
            index : Nat
        ) : ?Types.Response {
            switch (state.ledger._getOwner(index)) {
                case (?_) null;
                case _ ?http404(?"Token not yet minted.");
            };
        };


        ////////////////
        // Renderers //
        //////////////


        // Craft an HTTP response from an Asset Record.
        private func renderAsset (
            asset : AssetTypes.Record,
        ) : Types.Response {
            {
                body = state.assets._flattenPayload(asset.asset.payload);
                headers = [
                    ("Content-Type", asset.asset.contentType),
                    ("Access-Control-Allow-Origin", "*"),
                ];
                status_code = 200;
                streaming_strategy = null;
            }
        };


        // Renders an asset based with the given tags or 404.
        private func renderAssetWithTags (
            tags : [Text]
        ) : Types.Response {
            switch (state.assets._findTags(tags)) {
                case (?asset) renderAsset(asset);
                case null http404(?"Missing preview asset.");
            };
        };


        // Renders the legend preview threejs app with the given token index.
        private func renderLegendPreview (
            index : Nat
        ) : Types.Response {
            switch (mintedOr404(index)) {
                case (?err) return err;
                case _ ();
            };
            let app = switch (state.assets._findTag("preview-app")) {
                case (?a) {
                    switch (Text.decodeUtf8(state.assets._flattenPayload(a.asset.payload))) {
                        case (?t) t;
                        case _ "";
                    }
                };
                case _ return http404(?"Missing preview app.");
            };
            return {
                body = Text.encodeUtf8(
                    "<!doctype html>" #
                    "<html>" #
                        app #
                        "<script>window.legendIndex = " # Nat.toText(index) # "</script>" #
                    "</html>"
                );
                headers = [
                    ("Content-Type", "text/html"),
                    ("Cache-Control", "max-age=31536000"), // Cache one year
                ];
                status_code = 200;
                streaming_strategy = null;
            };
        };


        // Builds a legend manifest record.
        // This contains all of the assets and data relevant to an NFT.
        private func renderManifest (
            index : Nat,
        ) : AssetTypes.LegendManifest {
            let tokenId = Ext.TokenIdentifier.encode(Principal.fromText("nges7-giaaa-aaaaj-qaiya-cai"), Nat32.fromNat(index));
            let { back; border; ink; } = state.ledger.nfts(?index)[0];
            let nriBack = switch (Array.find<(Text, Float)>(state.ledger.NRI, func ((a, b)) { a == "back-" # back })) {
                case (?(_, i)) i;
                case _ 0.0;
            };
            let nriBorder = switch (Array.find<(Text, Float)>(state.ledger.NRI, func ((a, b)) { a == "border-" # border })) {
                case (?(_, i)) i;
                case _ 0.0;
            };
            let nriInk = switch (Array.find<(Text, Float)>(state.ledger.NRI, func ((a, b)) { a == "ink-" # ink })) {
                case (?(_, i)) i;
                case _ 0.0;
            };
            return {
                back;
                border;
                ink;
                nri = {
                    back = nriBack;
                    border = nriBorder;
                    ink = nriInk;
                    avg = (nriBack + nriBorder + nriInk) / 3;
                };
                maps = {
                    normal = do {
                        switch (state.assets._findTag("normal")) {
                            case (?a) a.meta.filename;
                            case _ "";
                        };
                    };
                    layers = do {
                        Array.map<AssetTypes.Record, AssetTypes.FilePath>(
                            state.assets._findAllTag("layer"),
                            func (record) {
                                record.meta.filename;
                            },
                        );
                    };
                    back = do {
                        switch (state.assets._findTags(["back", back])) {
                            case (?a) a.meta.filename;
                            case _ "";
                        };
                    };
                    border = do {
                        switch (state.assets._findTags(["border", border])) {
                            case (?a) a.meta.filename;
                            case _ "";
                        };
                    };
                    background = do {
                        switch (state.assets._findTag("background")) {
                            case (?a) a.meta.filename;
                            case _ "";
                        };
                    };
                };
                colors = do {
                    var map = {
                        base     = "#000000";
                        specular = "#000000";
                        emissive = "#000000";
                    };
                    for ((name, colors) in state.assets.inkColors.vals()) {
                        if (name == ink) map := colors;
                    };
                    map;
                };
                views = {
                    flat = do {
                        switch (state.assets._findTags(["preview", "flat"])) {
                            case (?a) "?type=card-art&tokenid=" # tokenId;
                            case _ "";
                        };
                    };
                    sideBySide = do {
                        switch (
                            state.assets._findTags([
                                "preview", "side-by-side", "back-" # back,
                                "border-" # border, "ink-" # ink
                            ])
                        ) {
                            case (?a) "?type=thumbnail&tokenid=" # tokenId;
                            case _ "";
                        };
                    };
                    animated = do {
                        switch (state.assets._findTags(["preview", "animated"])) {
                            case (?a) "?type=animated&tokenid=" # tokenId;
                            case _ "";
                        };
                    };
                    interactive = "?tokenid=" # tokenId;
                    manifest = "?type=manifest&tokenid=" # tokenId;  // TODO
                };
            }
        };


        ////////////////////
        // Path Handlers //
        //////////////////


        // @path: /asset/<text>/
        // @path: /assets/<text>/
        // Serves an asset based on filename.
        private func httpAssetFilename (path : ?Text) : Types.Response {
            switch (path) {
                case (?path) {
                    switch (state.assets.getAssetByName(path)) {
                        case (?asset) renderAsset(asset);
                        case _ http404(?"Asset not found.");
                    };
                };
                case _ return httpAssetManifest(path);
            };
        };


        // @path: /asset-manifest
        // Serves a JSON list of all assets in the canister.
        private func httpAssetManifest (path : ?Text) : Types.Response {
            {
                body = Text.encodeUtf8(
                    "[\n" #
                    Array.foldLeft<AssetTypes.Record, Text>(state.assets.getManifest(), "", func (a, b) {
                        let comma = switch (a == "") {
                            case true "\t";
                            case false ", ";
                        };
                        a # comma # "{\n" #
                            "\t\t\"filename\": \"" # b.meta.filename # "\",\n" #
                            "\t\t\"url\": \"/assets/" # b.meta.filename # "\",\n" #
                            "\t\t\"description\": \"" # b.meta.description # "\",\n" #
                            "\t\t\"tags\": [" # Array.foldLeft<Text, Text>(b.meta.tags, "", func (a, b) {
                                let comma = switch (a == "") {
                                    case true "";
                                    case false ", ";
                                };
                                a # comma # "\"" # b # "\""
                            }) # "]\n" #
                        "\t}";
                    }) #
                    "\n]"
                );
                headers = [
                    ("Content-Type", "application/json"),
                ];
                status_code = 200;
                streaming_strategy = null;
            }
        };


        // @path: /legend-manifest/<nat>/
        // Serves a JSON manifest of all assets required to render a particular legend
        private func httpLegendManifest (path : ?Text) : Types.Response {
            let index = switch (path) {
                case (?p) natFromText(p);
                case _ null;
            };
            switch (index) {
                case (?i) {
                    switch (mintedOr404(i)) {
                        case (?err) return err;
                        case _ ();
                    };
                    let manifest = renderManifest(i);
                    // No Motoko JSON lib supporting record types.
                    return {
                        body = Text.encodeUtf8("{\n" #
                            "\t\"back\"     : \"" # manifest.back # "\",\n" #
                            "\t\"border\"   : \"" # manifest.border # "\",\n" #
                            "\t\"ink\"      : \"" # manifest.ink # "\",\n" #
                            "\t\"nri\"      : {\n" #
                                "\t\t\"back\"       : " # Float.toText(manifest.nri.back) # ",\n" #
                                "\t\t\"border\"     : " # Float.toText(manifest.nri.border) # ",\n" #
                                "\t\t\"ink\"        : " # Float.toText(manifest.nri.ink) # ",\n" #
                                "\t\t\"avg\"        : " # Float.toText(manifest.nri.avg) # "\n" #
                            "\t},\n" #
                            "\t\"maps\"     : {\n" #
                                "\t\t\"normal\"     : \"/assets/" # manifest.maps.normal # "\",\n" #
                                "\t\t\"back\"       : \"/assets/" # manifest.maps.back # "\",\n" #
                                "\t\t\"border\"     : \"/assets/" # manifest.maps.border # "\",\n" #
                                "\t\t\"background\" : \"/assets/" # manifest.maps.background # "\",\n" #
                                "\t\t\"layers\"     : [\n" #
                                    Array.foldLeft<AssetTypes.FilePath, Text>(
                                        manifest.maps.layers,
                                        "",
                                        func (a, b) {
                                            let comma = switch (a == "") {
                                                case true "\t\t\t";
                                                case false ",\n\t\t\t";
                                            };
                                            return a # comma # "\"/assets/" # b # "\""
                                        },
                                    ) # "\n" #
                                "\t\t]\n" #
                            "\t},\n" #
                            "\t\"colors\": {\n" #
                                "\t\t\"base\"       : \"" # manifest.colors.base # "\",\n" #
                                "\t\t\"specular\"   : \"" # manifest.colors.specular # "\",\n" #
                                "\t\t\"emissive\"   : \"" # manifest.colors.emissive # "\"\n" #
                            "\t},\n" #
                            "\t\"views\": {\n" #
                                "\t\t\"flat\"       : \"" # manifest.views.flat # "\",\n" #
                                "\t\t\"sideBySide\" : \"" # manifest.views.sideBySide # "\",\n" #
                                "\t\t\"animated\"   : \"" # manifest.views.animated # "\",\n" #
                                "\t\t\"interactive\": \"" # manifest.views.interactive # "\"\n" #
                            "\t}\n" #
                        "\n}");
                        headers = [
                            ("Content-Type", "application/json"),
                            ("Access-Control-Allow-Origin", "*"),
                        ];
                        status_code = 200;
                        streaming_strategy = null;
                    };
                };
                case null http404(?"Invalid index.");
            }
        };


        // @path: /legend/<nat>/
        // Displays the NFT in the threejs app.
        // This is the de facto view for the NFTs.
        private func httpLegend (
            path : ?Text,
        ) : Types.Response {
            let index : ?Nat = switch (path) {
                case (?path) natFromText(path);
                case _ null;
            };
            switch (index) {
                case (?i) renderLegendPreview(i);
                case _ http404(?"Bad index.");
            }
        };


        // @path: /side-by-side-preview/<nat>/
        // Displays the static side-by-side image for an NFT.
        public func httpSideBySidePreview (
            path : ?Text,
        )  : Types.Response {
            let index : ?Nat = switch (path) {
                case (?path) natFromText(path);
                case _ null;
            };
            switch (index) {
                case (?i) {
                    let legend = state.ledger._getLegend(i);
                    renderAssetWithTags([
                        "preview", "side-by-side", "back-" # legend.back,
                        "border-" # legend.border, "ink-" # legend.ink
                    ]);
                };
                case _ http404(?"Invalid index.");
            };
        };


        // @path: /animated-preview/<nat>/
        // Displays the animated webm for an NFT.
        public func httpAnimatedPreview (
            path : ?Text,
        )  : Types.Response {
            let index : ?Nat = switch (path) {
                case (?path) natFromText(path);
                case _ null;
            };
            switch (index) {
                case (?i) {
                    let legend = state.ledger._getLegend(i);
                    renderAssetWithTags([
                        "preview", "animated", "back-" # legend.back,
                        "border-" # legend.border, "ink-" # legend.ink
                    ]);
                };
                case _ http404(?"Invalid index.");
            };
        };


        // @path: /
        private func httpIndex () : Types.Response {
            {
                body = "Pong!";
                headers = [
                    ("Content-Type", "text/plain"),
                ];
                status_code = 200;
                streaming_strategy = null;
            };
        };


        // @path: *?tokenid
        // This is kinda the main view for NFTs. Built to integrate well with Stoic and Entrepot.
        public func httpEXT(request : Types.Request) : Types.Response {
            let tokenId = Iter.toArray(Text.tokens(request.url, #text("tokenid=")))[1];
            let { index } = Stoic.decodeToken(tokenId);
            switch (mintedOr404(Nat32.toNat(index))) {
                case (?err) return err;
                case _ ();
            };
            if (Text.contains(request.url, #text("type=card-art"))) {
                return renderAssetWithTags(["preview", "flat"]);
            };
            let legend = state.ledger._getLegend(Nat32.toNat(index));
            if (Text.contains(request.url, #text("type=animated"))) {
                return renderAssetWithTags([
                    "preview", "animated", "back-" # legend.back,
                    "border-" # legend.border, "ink-" # legend.ink
                ]);
            };
            if (not Text.contains(request.url, #text("type=thumbnail"))) {
                return renderLegendPreview(Nat32.toNat(index));
            };
            renderAssetWithTags([
                "preview", "side-by-side", "back-" # legend.back,
                "border-" # legend.border, "ink-" # legend.ink
            ]);
        };

        
        // @path: *?tokenindex=<nat>
        // Displays the side-by-side preview.
        private func httpTokenIndex (request : Types.Request) : Types.Response {
            let index = Iter.toArray(Text.tokens(request.url, #text("tokenindex=")))[1];
            switch (natFromText(index)) {
                case (?i) {
                    let legend = state.ledger._getLegend(i);
                    renderAssetWithTags([
                        "preview", "side-by-side", "back-" # legend.back,
                        "border-" # legend.border, "ink-" # legend.ink
                    ]);
                };
                case _ http404(?"No token at that index.");
            };
        };


        // A 404 response with an optional error message.
        private func http404(msg : ?Text) : Types.Response {
            {
                body = Text.encodeUtf8(
                    switch (msg) {
                        case (?msg) msg;
                        case null "Not found.";
                    }
                );
                headers = [
                    ("Content-Type", "text/plain"),
                ];
                status_code = 404;
                streaming_strategy = null;
            };
        };


        // A 400 response with an optional error message.
        private func http400(msg : ?Text) : Types.Response {
            {
                body = Text.encodeUtf8(
                    switch (msg) {
                        case (?msg) msg;
                        case null "Bad request.";
                    }
                );
                headers = [
                    ("Content-Type", "text/plain"),
                ];
                status_code = 400;
                streaming_strategy = null;
            };
        };


        //////////////////
        // Path Config //
        ////////////////


        let paths : [(Text, (path: ?Text) -> Types.Response)] = [
            ("asset", httpAssetFilename),
            ("assets", httpAssetFilename),
            ("asset-manifest", httpAssetManifest),
            ("legend-manifest", httpLegendManifest),
            ("legend", httpLegend),
            ("side-by-side-preview", httpSideBySidePreview),
            ("animated-preview", httpAnimatedPreview),
        ];


        /////////////////////
        // Request Router //
        ///////////////////


        // This method is magically built into every canister on the IC
        // The request/response types used here are manually configured to mirror how that method works.
        public func request(request : Types.Request) : Types.Response {
            
            // Stoic wallet preview

            if (Text.contains(request.url, #text("tokenid"))) {
                return httpEXT(request);
            };

            if (Text.contains(request.url, #text("tokenindex"))) {
                return httpTokenIndex(request);
            };

            // Paths

            let path = Iter.toArray(Text.tokens(request.url, #text("/")));

            switch (path.size()) {
                case 0 return httpIndex();
                case 1 for ((key, handler) in Iter.fromArray(paths)) {
                    if (path[0] == key) return handler(null);
                };
                case 2 for ((key, handler) in Iter.fromArray(paths)) {
                    if (path[0] == key) return handler(?path[1]);
                };
                case _ for ((key, handler) in Iter.fromArray(paths)) {
                    if (path[0] == key) return handler(?path[1]);
                };
            };
            
            for ((key, handler) in Iter.fromArray(paths)) {
                if (path[0] == key) return handler(?path[1])
            };

            // 404

            return http404(?"Path not found.");
        };
    };
};
