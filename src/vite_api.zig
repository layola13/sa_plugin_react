const std = @import("std");
const parser = @import("react/parser.zig");
const lowerer = @import("react/lowerer.zig");
const reachability = @import("react/reachability.zig");
const airlock_gen = @import("react/airlock_gen.zig");
const sax_build = @import("react/build.zig");

pub const ReactArtifacts = struct {
    root_name: []u8,
    sa_code: std.ArrayList(u8),
    shared_sa_code: std.ArrayList(u8),
    component_sa_codes: std.ArrayList(std.ArrayList(u8)),
    airlock_js: std.ArrayList(u8),
    index_html: std.ArrayList(u8),

    pub fn deinit(self: *ReactArtifacts, allocator: std.mem.Allocator) void {
        allocator.free(self.root_name);
        self.sa_code.deinit();
        self.shared_sa_code.deinit();
        for (self.component_sa_codes.items) |*code| code.deinit();
        self.component_sa_codes.deinit();
        self.airlock_js.deinit();
        self.index_html.deinit();
        self.* = undefined;
    }
};

pub const SourceUnit = sax_build.SourceUnit;

fn appendComponentSansExternBlock(out: *std.ArrayList(u8), text: []const u8) !void {
    var cursor: usize = 0;
    var in_extern_block = false;
    while (cursor < text.len) {
        const line_end = std.mem.indexOfScalarPos(u8, text, cursor, '\n') orelse text.len;
        const next_cursor = if (line_end < text.len) line_end + 1 else text.len;
        const line = std.mem.trimRight(u8, text[cursor..line_end], "\r");

        if (!in_extern_block) {
            if (std.mem.startsWith(u8, line, "@extern ")) {
                in_extern_block = true;
            } else {
                try out.appendSlice(text[cursor..next_cursor]);
            }
        } else {
            if (line.len == 0 or std.mem.startsWith(u8, line, "@extern ")) {
                cursor = next_cursor;
                continue;
            }
            try out.appendSlice(text[cursor..]);
            return;
        }

        cursor = next_cursor;
    }
}

fn sourceStem(path: []const u8) []const u8 {
    const basename = std.fs.path.basename(path);
    const dot_idx = std.mem.lastIndexOfScalar(u8, basename, '.') orelse basename.len;
    return basename[0..dot_idx];
}

fn lowercaseName(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    const out = try allocator.dupe(u8, text);
    for (out) |*c| c.* = std.ascii.toLower(c.*);
    return out;
}

fn fileExists(path: []const u8) bool {
    var file = std.fs.cwd().openFile(path, .{}) catch return false;
    file.close();
    return true;
}

fn readSource(allocator: std.mem.Allocator, sax_file: []const u8, stderr: anytype) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, sax_file, 16 * 1024 * 1024) catch |err| {
        try stderr.print("error[SA-REACT-IO]: failed to read {s}: {s}\n", .{ sax_file, @errorName(err) });
        return error.ReadFailed;
    };
}

fn firstPathSegment(path: []const u8) []const u8 {
    const normalized = std.mem.trimLeft(u8, path, "/\\");
    const slash = std.mem.indexOfAny(u8, normalized, "/\\") orelse normalized.len;
    return normalized[0..slash];
}

fn candidateIncludePath(allocator: std.mem.Allocator, base_dir: []const u8, include_file: []const u8) !?[]u8 {
    const candidate = try std.fs.path.join(allocator, &.{ base_dir, include_file });
    errdefer allocator.free(candidate);
    if (fileExists(candidate)) return candidate;
    allocator.free(candidate);
    return null;
}

fn findIncludeInPathList(allocator: std.mem.Allocator, env_name: []const u8, include_file: []const u8) !?[]u8 {
    const value = std.process.getEnvVarOwned(allocator, env_name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(value);

    var parts = std.mem.splitScalar(u8, value, ':');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (try candidateIncludePath(allocator, part, include_file)) |path| return path;
    }
    return null;
}

fn findIncludeNearLoadedPlugins(allocator: std.mem.Allocator, include_file: []const u8) !?[]u8 {
    const value = std.process.getEnvVarOwned(allocator, "SA_PLUGINS_PATH") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(value);

    var parts = std.mem.splitScalar(u8, value, ':');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        const lib_dir = std.fs.path.dirname(part) orelse part;

        const sibling_share = try std.fs.path.join(allocator, &.{ lib_dir, "share" });
        defer allocator.free(sibling_share);
        if (try candidateIncludePath(allocator, sibling_share, include_file)) |path| return path;

        if (std.fs.path.dirname(lib_dir)) |prefix_dir| {
            const prefix_share = try std.fs.path.join(allocator, &.{ prefix_dir, "share" });
            defer allocator.free(prefix_share);
            if (try candidateIncludePath(allocator, prefix_share, include_file)) |path| return path;
        }
    }
    return null;
}

fn findInstalledPluginInclude(allocator: std.mem.Allocator, include_file: []const u8) !?[]u8 {
    const plugin_name = firstPathSegment(include_file);
    if (plugin_name.len == 0) return null;

    const home = std.process.getEnvVarOwned(allocator, "SA_PLUGINS_HOME") catch |home_err| switch (home_err) {
        error.EnvironmentVariableNotFound => blk: {
            const user_home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
                error.EnvironmentVariableNotFound => return null,
                else => return err,
            };
            defer allocator.free(user_home);
            break :blk try std.fs.path.join(allocator, &.{ user_home, ".local", "share", "sa_plugins" });
        },
        else => return home_err,
    };
    defer allocator.free(home);

    const installed_share = try std.fs.path.join(allocator, &.{ home, "installed", plugin_name, "current", "share" });
    defer allocator.free(installed_share);
    return try candidateIncludePath(allocator, installed_share, include_file);
}

fn findDevPluginInclude(allocator: std.mem.Allocator, include_file: []const u8) !?[]u8 {
    const plugin_name = firstPathSegment(include_file);
    if (plugin_name.len == 0) return null;
    const plugin_dir = try std.fmt.allocPrint(allocator, "sa_plugin_{s}", .{plugin_name});
    defer allocator.free(plugin_dir);
    const dev_share = try std.fs.path.join(allocator, &.{ "/home/vscode/projects/sa_plugins", plugin_dir, "zig-out", "share" });
    defer allocator.free(dev_share);
    return try candidateIncludePath(allocator, dev_share, include_file);
}

pub fn resolveIncludePath(allocator: std.mem.Allocator, sax_file: []const u8, include_file: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(include_file)) return allocator.dupe(u8, include_file);
    const base_dir = std.fs.path.dirname(sax_file) orelse ".";
    const relative = try std.fs.path.join(allocator, &.{ base_dir, include_file });
    errdefer allocator.free(relative);
    if (fileExists(relative)) return relative;
    allocator.free(relative);

    const cwd_relative = try allocator.dupe(u8, include_file);
    errdefer allocator.free(cwd_relative);
    if (fileExists(cwd_relative)) return cwd_relative;
    allocator.free(cwd_relative);

    if (try findIncludeInPathList(allocator, "SA_REACT_INCLUDE_PATH", include_file)) |path| return path;
    if (try findIncludeNearLoadedPlugins(allocator, include_file)) |path| return path;
    if (try findInstalledPluginInclude(allocator, include_file)) |path| return path;
    if (try findDevPluginInclude(allocator, include_file)) |path| return path;

    return std.fs.path.join(allocator, &.{ base_dir, include_file });
}

pub fn readComposedSource(allocator: std.mem.Allocator, sax_file: []const u8, includes: []const []const u8, stderr: anytype) ![]u8 {
    const source = try readSource(allocator, sax_file, stderr);
    errdefer allocator.free(source);
    if (includes.len == 0) return source;

    var composed = std.ArrayList(u8).init(allocator);
    errdefer composed.deinit();
    try composed.appendSlice(source);
    if (composed.items.len == 0 or composed.items[composed.items.len - 1] != '\n') try composed.append('\n');

    for (includes) |include_file| {
        const include_path = try resolveIncludePath(allocator, sax_file, include_file);
        defer allocator.free(include_path);
        const include_source = try readSource(allocator, include_path, stderr);
        defer allocator.free(include_source);
        try composed.append('\n');
        try composed.appendSlice(include_source);
        if (composed.items.len == 0 or composed.items[composed.items.len - 1] != '\n') try composed.append('\n');
    }

    allocator.free(source);
    return try composed.toOwnedSlice();
}

pub fn compileBrowserArtifacts(
    allocator: std.mem.Allocator,
    sax_file: []const u8,
    includes: []const []const u8,
    stderr: anytype,
) !ReactArtifacts {
    const source = try readComposedSource(allocator, sax_file, includes, stderr);
    defer allocator.free(source);

    var sax_parser = parser.SaxParser.init(allocator, source);
    var program = sax_parser.parse() catch |err| {
        try stderr.print("error[SA-REACT-PARSE]: {s}: {s}\n", .{ sax_file, @errorName(err) });
        return error.ReactCompileFailed;
    };
    defer program.deinit();

    if (program.components.len == 0) {
        try stderr.print("error[SA-REACT-CHECK]: InvalidComponentBody while parsing {s}\n", .{sax_file});
        return error.ReactCompileFailed;
    }

    var sa_code = std.ArrayList(u8).init(allocator);
    errdefer sa_code.deinit();
    const reachable_components = try reachability.collectReachableComponents(allocator, program.components);
    defer allocator.free(reachable_components);

    var shared_sa_code = std.ArrayList(u8).init(allocator);
    errdefer shared_sa_code.deinit();

    var root_lowerer = try lowerer.SaxLowerer.initWithProgram(allocator, reachable_components, program.components[0]);
    defer root_lowerer.deinit();
    root_lowerer.lower(&shared_sa_code, .{ .shared_decls = .runtime_only, .emit_app_alias = true }) catch |err| {
        try stderr.print("error[SA-REACT-LOWER]: shared runtime for {s} failed: {s}\n", .{ program.components[0].name, @errorName(err) });
        return err;
    };

    var component_sa_codes = std.ArrayList(std.ArrayList(u8)).init(allocator);
    errdefer {
        for (component_sa_codes.items) |*code| code.deinit();
        component_sa_codes.deinit();
    }

    try sa_code.appendSlice(shared_sa_code.items);
    if (sa_code.items.len != 0 and sa_code.items[sa_code.items.len - 1] != '\n') try sa_code.append('\n');

    for (reachable_components, 0..) |component, idx| {
        var component_code = std.ArrayList(u8).init(allocator);
        errdefer component_code.deinit();

        var sax_lowerer = try lowerer.SaxLowerer.initWithProgram(allocator, reachable_components, component);
        defer sax_lowerer.deinit();
        sax_lowerer.lower(&component_code, .{ .shared_decls = .component_externs }) catch |err| {
            try stderr.print("error[SA-REACT-LOWER]: component {s} failed: {s}\n", .{ component.name, @errorName(err) });
            return err;
        };

        if (idx != 0) try sa_code.writer().writeByte('\n');
        try appendComponentSansExternBlock(&sa_code, component_code.items);
        if (sa_code.items.len != 0 and sa_code.items[sa_code.items.len - 1] != '\n') try sa_code.append('\n');
        try component_sa_codes.append(component_code);
    }

    const root_name = try lowercaseName(allocator, program.components[0].name);
    errdefer allocator.free(root_name);

    var airlock_generator = airlock_gen.AirlockGenerator.init(allocator);
    const airlock_js = try airlock_generator.generateAirlockJS();
    errdefer airlock_js.deinit();
    const index_html = try airlock_generator.generateIndexHTML(sourceStem(sax_file), "app.wasm");
    errdefer index_html.deinit();

    return .{
        .root_name = root_name,
        .sa_code = sa_code,
        .shared_sa_code = shared_sa_code,
        .component_sa_codes = component_sa_codes,
        .airlock_js = airlock_js,
        .index_html = index_html,
    };
}

pub fn sourceUnitsFromArtifacts(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    artifacts: *const ReactArtifacts,
) !std.ArrayList(SourceUnit) {
    var units = std.ArrayList(SourceUnit).init(allocator);
    errdefer {
        for (units.items) |unit| allocator.free(unit.logical_name);
        units.deinit();
    }

    try units.append(.{
        .logical_name = blk: {
            const name = try allocator.dupe(u8, "shared");
            errdefer allocator.free(name);
            break :blk name;
        },
        .source_path = source_path,
        .source_text = artifacts.shared_sa_code.items,
    });

    for (artifacts.component_sa_codes.items, 0..) |component_code, idx| {
        const logical_name = try std.fmt.allocPrint(allocator, "component_{d}", .{idx});
        errdefer allocator.free(logical_name);
        try units.append(.{
            .logical_name = logical_name,
            .source_path = source_path,
            .source_text = component_code.items,
        });
    }

    return units;
}

pub fn freeSourceUnits(allocator: std.mem.Allocator, units: *std.ArrayList(SourceUnit)) void {
    for (units.items) |unit| allocator.free(unit.logical_name);
    units.deinit();
}

pub fn buildBrowserWasmFromSourceText(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source_text: []const u8,
    out_path: []const u8,
    debug: bool,
    optimization: anytype,
    stderr: anytype,
) !u8 {
    return sax_build.buildBrowserWasmFromSourceText(allocator, source_path, source_text, out_path, debug, optimization, .{ .jobs = 1, .dce = .full }, stderr);
}

pub fn buildBrowserWasmFromSourceUnits(
    allocator: std.mem.Allocator,
    units: []const SourceUnit,
    out_path: []const u8,
    debug: bool,
    optimization: anytype,
    stderr: anytype,
) !u8 {
    return sax_build.buildBrowserWasmFromSourceUnits(allocator, units, out_path, debug, optimization, .{ .jobs = 1, .dce = .full }, stderr);
}

test "react vite api resolves dev plugin include" {
    const path = try resolveIncludePath(std.testing.allocator, "demos/app.sax", "mui/material.sax");
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.endsWith(u8, path, "mui/material.sax"));
}

test "react vite api resolves includes relative to cwd before plugin installs" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("demos");
    try tmp.dir.makePath("mui");
    try tmp.dir.writeFile(.{ .sub_path = "demos/app.sax", .data = "<Component name=\"App\"><div /></Component>" });
    try tmp.dir.writeFile(.{ .sub_path = "mui/material.sax", .data = "<Component name=\"LocalMui\"><div /></Component>" });

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    const path = try resolveIncludePath(std.testing.allocator, "demos/app.sax", "mui/material.sax");
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("mui/material.sax", path);
}
