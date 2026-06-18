const std = @import("std");
const plugin_api = @import("plugin_api");
const parser = @import("react/parser.zig");
const lowerer = @import("react/lowerer.zig");
const reachability = @import("react/reachability.zig");
const airlock_gen = @import("react/airlock_gen.zig");
const sax_build = @import("react/build.zig");

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

const skills = [_]plugin_api.SkillSection{
    .{
        .name = "react",
        .summary = "Standalone React-on-SAX project commands",
        .items = &.{
            "react build <file> [--include <file.sax>] [--out-dir <dir>]",
            "react check <file> [--include <file.sax>]",
            "react dev <file> [--include <file.sax>] [--out-dir <dir>]",
            "react new <name>",
        },
    },
};

const SaxArtifacts = struct {
    component_name: []const u8,
    root_name: []u8,
    sa_code: std.ArrayList(u8),
    shared_sa_code: ?std.ArrayList(u8),
    component_sa_codes: ?std.ArrayList(std.ArrayList(u8)),
    airlock_js: std.ArrayList(u8),
    wgpu_airlock_js: ?std.ArrayList(u8),
    sa3d_airlock_js: ?std.ArrayList(u8),
    index_html: std.ArrayList(u8),

    fn deinit(self: *SaxArtifacts, allocator: std.mem.Allocator) void {
        allocator.free(self.root_name);
        self.sa_code.deinit();
        if (self.shared_sa_code) |*shared| shared.deinit();
        if (self.component_sa_codes) |*codes| {
            for (codes.items) |*code| code.deinit();
            codes.deinit();
        }
        self.airlock_js.deinit();
        if (self.wgpu_airlock_js) |*js| js.deinit();
        if (self.sa3d_airlock_js) |*js| js.deinit();
        self.index_html.deinit();
        self.* = undefined;
    }
};

const SidecarSupport = struct {
    prelude: std.ArrayList(u8),
    airlock_js: std.ArrayList(u8),

    fn deinit(self: *SidecarSupport) void {
        self.prelude.deinit();
        self.airlock_js.deinit();
        self.* = undefined;
    }
};

const SidecarSpec = struct {
    label: []const u8,
    error_tag: []const u8,
    share_env: []const u8,
    share_env_alt: ?[]const u8 = null,
    airlock_env: []const u8,
    installed_name: []const u8,
    lib_name: []const u8,
    path_token: []const u8,
    dev_share_dir: []const u8,
    sai_file: []const u8,
    sal_file: []const u8,
    airlock_file: []const u8,
};

const ReactSourceOptions = struct {
    source_file: []const u8,
    out_dir: ?[]const u8 = null,
    includes: []const []const u8,

    fn deinit(self: *ReactSourceOptions, allocator: std.mem.Allocator) void {
        allocator.free(self.includes);
        self.* = undefined;
    }
};

const ShardedSaxArtifacts = struct {
    shared_sa_code: std.ArrayList(u8),
    component_sa_codes: std.ArrayList(std.ArrayList(u8)),
    airlock_js: std.ArrayList(u8),
    wgpu_airlock_js: ?std.ArrayList(u8),
    sa3d_airlock_js: ?std.ArrayList(u8),
    index_html: std.ArrayList(u8),

    fn deinit(self: *ShardedSaxArtifacts, allocator: std.mem.Allocator) void {
        self.shared_sa_code.deinit();
        for (self.component_sa_codes.items) |*code| code.deinit();
        self.component_sa_codes.deinit();
        self.airlock_js.deinit();
        if (self.wgpu_airlock_js) |*js| js.deinit();
        if (self.sa3d_airlock_js) |*js| js.deinit();
        self.index_html.deinit();
        self.* = undefined;
        _ = allocator;
    }
};

const wgpu_sidecar = SidecarSpec{
    .label = "WGPU",
    .error_tag = "SA-REACT-WGPU",
    .share_env = "SA_WGPU_SHARE_DIR",
    .airlock_env = "SA_WGPU_AIRLOCK_JS",
    .installed_name = "wgpu",
    .lib_name = "libwgpu.so",
    .path_token = "sa_plugin_wgpu",
    .dev_share_dir = "/home/vscode/projects/sa_plugins/sa_plugin_wgpu/zig-out/share",
    .sai_file = "wgpu.sai",
    .sal_file = "wgpu.sal",
    .airlock_file = "wgpu_airlock.js",
};

const sa3d_sidecar = SidecarSpec{
    .label = "SA3D",
    .error_tag = "SA-REACT-SA3D",
    .share_env = "SA_3D_SHARE_DIR",
    .share_env_alt = "SA3D_SHARE_DIR",
    .airlock_env = "SA_3D_AIRLOCK_JS",
    .installed_name = "3d",
    .lib_name = "lib3d.so",
    .path_token = "sa_plugin_3d",
    .dev_share_dir = "/home/vscode/projects/sa_plugins/sa_plugin_3dengines/sa_plugin_3d/zig-out/share",
    .sai_file = "sa3d.sai",
    .sal_file = "sa3d.sal",
    .airlock_file = "sa3d_airlock.js",
};

const ValidationError = enum {
    SaxStateLeak,
    SaxEventEscape,
    SaxRenderOutsideHandler,
    SaxInvalidInterpolation,
    SaxStateWriteFromOutside,
    SaxInvalidNativeEscape,
};

const ValidationFailure = struct {
    component_name: []const u8,
    err: ValidationError,
    line: u32,
    text: []const u8,
};

fn cArgvToSlice(argv: [*]const [*:0]const u8, argv_len: usize, allocator: std.mem.Allocator) ![]const []const u8 {
    const slice = argv[0..argv_len];
    var out = try allocator.alloc([]const u8, slice.len);
    errdefer allocator.free(out);
    for (slice, 0..) |arg, idx| out[idx] = std.mem.span(arg);
    return out;
}

fn isReactCliError(err: anyerror) bool {
    return switch (err) {
        error.MissingSourcePath,
        error.UnexpectedArgument,
        error.UnknownCommand,
        error.InvalidPath,
        error.FileNotFound,
        error.NotDir,
        error.AccessDenied,
        => true,
        else => false,
    };
}

fn writeSaxCliError(writer: std.io.AnyWriter, argv: []const []const u8, err: anyerror) !void {
    const sub = if (argv.len >= 3) argv[2] else "";
    const message = switch (err) {
        error.MissingSourcePath => "missing required React operand",
        error.UnexpectedArgument => "unexpected React argument",
        error.UnknownCommand => "unknown React subcommand",
        error.InvalidPath => "invalid React path",
        error.FileNotFound => "React file or directory not found",
        error.NotDir => "React path is not a directory",
        error.AccessDenied => "React path access denied",
        else => @errorName(err),
    };
    const help = if (err == error.MissingSourcePath and sub.len == 0)
        "usage: sa react <build|check|dev|new> <file-or-project>"
    else if (std.mem.eql(u8, sub, "build"))
        "usage: sa react build <file.sax> [--include <file.sax>] [--out-dir <dir>]"
    else if (std.mem.eql(u8, sub, "check"))
        "usage: sa react check <file.sax> [--include <file.sax>]"
    else if (std.mem.eql(u8, sub, "dev"))
        "usage: sa react dev <file.sax> [--include <file.sax>] [--out-dir <dir>]"
    else if (std.mem.eql(u8, sub, "new"))
        "usage: sa react new <project-name>"
    else
        "usage: sa react <build|check|dev|new> <file-or-project>";
    try writer.print("error[SA-REACT-CLI]: {s}\n  help: {s}\n", .{ message, help });
}

fn reactCliExitCode(err: anyerror) u8 {
    return switch (err) {
        error.UnknownCommand,
        error.MissingSourcePath,
        error.UnexpectedArgument,
        => 2,
        error.InvalidPath,
        error.FileNotFound,
        error.NotDir,
        error.AccessDenied,
        => 3,
        else => 1,
    };
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

fn ensureParentDir(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len != 0) try std.fs.cwd().makePath(dir);
    }
}

fn writeAllFile(path: []const u8, bytes: []const u8) !void {
    try ensureParentDir(path);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn readSource(allocator: std.mem.Allocator, sax_file: []const u8, stderr: std.io.AnyWriter) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, sax_file, 16 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        error.AccessDenied => return error.AccessDenied,
        error.IsDir => return error.NotDir,
        else => {
            try stderr.print("error[SA-REACT-IO]: failed to read {s}: {s}\n", .{ sax_file, @errorName(err) });
            return error.InvalidPath;
        },
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

fn resolveIncludePath(allocator: std.mem.Allocator, sax_file: []const u8, include_file: []const u8) ![]u8 {
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

fn readComposedSource(allocator: std.mem.Allocator, sax_file: []const u8, includes: []const []const u8, stderr: std.io.AnyWriter) ![]u8 {
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

fn sourceUsesWgpu(source: []const u8) bool {
    return std.mem.containsAtLeast(u8, source, 1, "renderer=\"wgpu\"") or
        std.mem.containsAtLeast(u8, source, 1, "sa_wgpu_") or
        std.mem.containsAtLeast(u8, source, 1, "WGPU_CUBE_");
}

fn sourceUsesSa3d(source: []const u8) bool {
    return std.mem.containsAtLeast(u8, source, 1, "renderer=\"sa3d\"") or
        std.mem.containsAtLeast(u8, source, 1, "sa3d_") or
        std.mem.containsAtLeast(u8, source, 1, "SA3D_");
}

fn fileExists(path: []const u8) bool {
    var file = std.fs.cwd().openFile(path, .{}) catch return false;
    file.close();
    return true;
}

fn addOwnedCandidate(candidates: *std.ArrayList([]u8), candidate: []u8) !void {
    errdefer candidates.allocator.free(candidate);
    for (candidates.items) |existing| {
        if (std.mem.eql(u8, existing, candidate)) {
            candidates.allocator.free(candidate);
            return;
        }
    }
    try candidates.append(candidate);
}

fn addEnvDirCandidate(allocator: std.mem.Allocator, candidates: *std.ArrayList([]u8), env_name: []const u8) !void {
    const value = std.process.getEnvVarOwned(allocator, env_name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return,
        else => return err,
    };
    try addOwnedCandidate(candidates, value);
}

fn addEnvAirlockDirCandidate(allocator: std.mem.Allocator, candidates: *std.ArrayList([]u8), env_name: []const u8) !void {
    const value = std.process.getEnvVarOwned(allocator, env_name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return,
        else => return err,
    };
    defer allocator.free(value);
    const dir = std.fs.path.dirname(value) orelse return;
    try addOwnedCandidate(candidates, try allocator.dupe(u8, dir));
}

fn addShareDirFromPluginLib(allocator: std.mem.Allocator, candidates: *std.ArrayList([]u8), spec: SidecarSpec, lib_path: []const u8) !void {
    const basename = std.fs.path.basename(lib_path);
    if (!std.mem.eql(u8, basename, spec.lib_name) and !std.mem.containsAtLeast(u8, lib_path, 1, spec.path_token)) return;
    const lib_dir = std.fs.path.dirname(lib_path) orelse return;
    try addOwnedCandidate(candidates, try std.fs.path.join(allocator, &.{ lib_dir, "share" }));
    const prefix_dir = std.fs.path.dirname(lib_dir) orelse return;
    try addOwnedCandidate(candidates, try std.fs.path.join(allocator, &.{ prefix_dir, "share" }));
}

fn addInstalledShareCandidate(allocator: std.mem.Allocator, candidates: *std.ArrayList([]u8), spec: SidecarSpec) !void {
    const home = std.process.getEnvVarOwned(allocator, "SA_PLUGINS_HOME") catch |home_err| switch (home_err) {
        error.EnvironmentVariableNotFound => blk: {
            const user_home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
                error.EnvironmentVariableNotFound => return,
                else => return err,
            };
            defer allocator.free(user_home);
            break :blk try std.fs.path.join(allocator, &.{ user_home, ".local", "share", "sa_plugins" });
        },
        else => return home_err,
    };
    defer allocator.free(home);
    try addOwnedCandidate(candidates, try std.fs.path.join(allocator, &.{ home, "installed", spec.installed_name, "current", "share" }));
}

fn addPluginPathCandidates(allocator: std.mem.Allocator, candidates: *std.ArrayList([]u8), spec: SidecarSpec) !void {
    const value = std.process.getEnvVarOwned(allocator, "SA_PLUGINS_PATH") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return,
        else => return err,
    };
    defer allocator.free(value);

    var parts = std.mem.splitScalar(u8, value, ':');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        try addShareDirFromPluginLib(allocator, candidates, spec, part);
    }
}

fn findSidecarShareDir(allocator: std.mem.Allocator, spec: SidecarSpec) !?[]u8 {
    var candidates = std.ArrayList([]u8).init(allocator);
    defer {
        for (candidates.items) |candidate| allocator.free(candidate);
        candidates.deinit();
    }

    try addEnvDirCandidate(allocator, &candidates, spec.share_env);
    if (spec.share_env_alt) |env_name| try addEnvDirCandidate(allocator, &candidates, env_name);
    try addEnvAirlockDirCandidate(allocator, &candidates, spec.airlock_env);
    try addPluginPathCandidates(allocator, &candidates, spec);
    try addInstalledShareCandidate(allocator, &candidates, spec);
    try addOwnedCandidate(&candidates, try allocator.dupe(u8, spec.dev_share_dir));

    for (candidates.items) |candidate| {
        const sai_path = try std.fs.path.join(allocator, &.{ candidate, spec.sai_file });
        defer allocator.free(sai_path);
        const sal_path = try std.fs.path.join(allocator, &.{ candidate, spec.sal_file });
        defer allocator.free(sal_path);
        const airlock_path = try std.fs.path.join(allocator, &.{ candidate, spec.airlock_file });
        defer allocator.free(airlock_path);
        if (fileExists(sai_path) and fileExists(sal_path) and fileExists(airlock_path)) {
            return try allocator.dupe(u8, candidate);
        }
    }
    return null;
}

fn loadSidecarSupport(allocator: std.mem.Allocator, stderr: std.io.AnyWriter, spec: SidecarSpec) !SidecarSupport {
    const share_dir = (try findSidecarShareDir(allocator, spec)) orelse {
        try stderr.print("error[{s}]: {s} React source requires sidecar files; install sa_plugin_{s}, set {s}, or include {s} in SA_PLUGINS_PATH\n", .{
            spec.error_tag,
            spec.label,
            spec.installed_name,
            spec.share_env,
            spec.lib_name,
        });
        return error.SaxCheckFailed;
    };
    defer allocator.free(share_dir);

    const sai_path = try std.fs.path.join(allocator, &.{ share_dir, spec.sai_file });
    defer allocator.free(sai_path);
    const sal_path = try std.fs.path.join(allocator, &.{ share_dir, spec.sal_file });
    defer allocator.free(sal_path);
    const airlock_path = try std.fs.path.join(allocator, &.{ share_dir, spec.airlock_file });
    defer allocator.free(airlock_path);

    const sai = try std.fs.cwd().readFileAlloc(allocator, sai_path, 1024 * 1024);
    defer allocator.free(sai);
    const sal = try std.fs.cwd().readFileAlloc(allocator, sal_path, 4 * 1024 * 1024);
    defer allocator.free(sal);

    var prelude = std.ArrayList(u8).init(allocator);
    errdefer prelude.deinit();
    try prelude.appendSlice(sai);
    if (prelude.items.len == 0 or prelude.items[prelude.items.len - 1] != '\n') try prelude.append('\n');
    try prelude.appendSlice(sal);
    if (prelude.items.len == 0 or prelude.items[prelude.items.len - 1] != '\n') try prelude.append('\n');
    try prelude.append('\n');

    var airlock_js = std.ArrayList(u8).init(allocator);
    errdefer airlock_js.deinit();
    const airlock_bytes = try std.fs.cwd().readFileAlloc(allocator, airlock_path, 4 * 1024 * 1024);
    defer allocator.free(airlock_bytes);
    try airlock_js.appendSlice(airlock_bytes);

    return .{ .prelude = prelude, .airlock_js = airlock_js };
}

fn parseErrorName(err: parser.ParseError) []const u8 {
    return switch (err) {
        parser.ParseError.UnknownTag => "SaxUnknownTag",
        parser.ParseError.UnknownEvent => "SaxUnknownEvent",
        parser.ParseError.InvalidAttribute => "SaxInvalidAttribute",
        parser.ParseError.InvalidNativeEscape => "SaxInvalidNativeEscape",
        else => @errorName(err),
    };
}

fn writeParseError(stderr: std.io.AnyWriter, sax_file: []const u8, err: parser.ParseError) !void {
    try stderr.print("error[SA-REACT-CHECK]: {s} while parsing {s}\n", .{ parseErrorName(err), sax_file });
}

fn validationErrorName(err: ValidationError) []const u8 {
    return switch (err) {
        .SaxStateLeak => "SaxStateLeak",
        .SaxEventEscape => "SaxEventEscape",
        .SaxRenderOutsideHandler => "SaxRenderOutsideHandler",
        .SaxInvalidInterpolation => "SaxInvalidInterpolation",
        .SaxStateWriteFromOutside => "SaxStateWriteFromOutside",
        .SaxInvalidNativeEscape => "SaxInvalidNativeEscape",
    };
}

fn writeValidationFailure(stderr: std.io.AnyWriter, failure: ValidationFailure) !void {
    try stderr.print("error[SA-REACT-CHECK]: {s} in component {s}", .{
        validationErrorName(failure.err),
        failure.component_name,
    });
    if (failure.line != 0) try stderr.print(" at line {d}", .{failure.line});
    try stderr.writeByte('\n');
    if (failure.text.len != 0) try stderr.print("  source: {s}\n", .{failure.text});
}

fn hasNativeEscape(text: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len >= 2 and trimmed[0] == '$' and trimmed[trimmed.len - 1] == '$') return true;
    }
    return false;
}

fn findEventHandler(component: parser.Component, handler_name: []const u8) bool {
    for (component.handlers) |handler| {
        if (std.mem.eql(u8, handler.name, handler_name)) return true;
    }
    return false;
}

fn interpolationIsInvalid(expr: parser.Expr) bool {
    return std.mem.indexOfAny(u8, expr.expr, "^!") != null;
}

fn trimValidationParens(text: []const u8) []const u8 {
    var current = std.mem.trim(u8, text, " \t\r\n");
    while (current.len >= 2 and current[0] == '(' and current[current.len - 1] == ')') {
        var quote: u8 = 0;
        var escaped = false;
        var depth: usize = 0;
        var wraps = true;
        for (current, 0..) |c, idx| {
            if (quote != 0) {
                if (escaped) {
                    escaped = false;
                } else if (c == '\\') {
                    escaped = true;
                } else if (c == quote) {
                    quote = 0;
                }
                continue;
            }
            if (c == '"' or c == '\'') {
                quote = c;
                continue;
            }
            if (c == '(') depth += 1;
            if (c == ')') {
                if (depth == 0) return current;
                depth -= 1;
                if (depth == 0 and idx != current.len - 1) {
                    wraps = false;
                    break;
                }
            }
        }
        if (!wraps or quote != 0 or depth != 0) return current;
        current = std.mem.trim(u8, current[1 .. current.len - 1], " \t\r\n");
    }
    return current;
}

fn validationSimpleName(text: []const u8) bool {
    const name = std.mem.trim(u8, text, " \t\r\n");
    if (name.len == 0 or !std.ascii.isAlphabetic(name[0]) and name[0] != '_') return false;
    for (name[1..]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    }
    return true;
}

fn findValidationTopLevelToken(text: []const u8, token: []const u8) ?usize {
    if (token.len == 0) return null;
    var quote: u8 = 0;
    var escaped = false;
    var depth: usize = 0;
    var idx: usize = 0;
    while (idx < text.len) : (idx += 1) {
        const c = text[idx];
        if (quote != 0) {
            if (escaped) {
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == quote) {
                quote = 0;
            }
            continue;
        }
        if (c == '"' or c == '\'') {
            quote = c;
            continue;
        }
        if (c == '(' or c == '{' or c == '[') {
            depth += 1;
            continue;
        }
        if (c == ')' or c == '}' or c == ']') {
            if (depth == 0) return null;
            depth -= 1;
            continue;
        }
        if (depth == 0 and std.mem.startsWith(u8, text[idx..], token)) return idx;
    }
    return null;
}

fn objectSpreadInterpolationIsInvalid(expr: parser.Expr) bool {
    if (std.mem.indexOfScalar(u8, expr.expr, '^') != null) return true;
    if (std.mem.indexOfScalar(u8, expr.expr, '!') == null) return false;

    const text = trimValidationParens(expr.expr);
    const op_idx = findValidationTopLevelToken(text, "&&") orelse findValidationTopLevelToken(text, "||") orelse return true;
    const condition_text = std.mem.trim(u8, text[0..op_idx], " \t\r\n");
    if (condition_text.len == 0 or condition_text[0] != '!') return true;
    const condition_name = trimValidationParens(condition_text[1..]);
    if (!validationSimpleName(condition_name)) return true;
    return std.mem.indexOfScalar(u8, text[op_idx + 2 ..], '!') != null;
}

fn findValidationFailure(allocator: std.mem.Allocator, component: parser.Component) ?ValidationFailure {
    var released = std.StringHashMap(void).init(allocator);
    defer released.deinit();
    for (component.release_vars) |name| released.put(name, {}) catch return null;

    for (component.state_vars) |sv| {
        if (!released.contains(sv.name)) {
            return .{ .component_name = component.name, .err = .SaxStateLeak, .line = 1, .text = sv.name };
        }
    }

    for (component.dom_nodes) |node| {
        for (node.attrs) |attr| {
            if (attr.is_event) {
                const handler_name = attr.event_handler orelse {
                    return .{ .component_name = component.name, .err = .SaxEventEscape, .line = 1, .text = attr.name };
                };
                if (!findEventHandler(component, handler_name)) {
                    return .{ .component_name = component.name, .err = .SaxEventEscape, .line = 1, .text = handler_name };
                }
            }
            switch (attr.value) {
                .literal => {},
                .interpolation => |expr| if (interpolationIsInvalid(expr)) {
                    return .{ .component_name = component.name, .err = .SaxInvalidInterpolation, .line = 1, .text = expr.expr };
                },
                .template => |pieces| {
                    for (pieces) |piece| switch (piece) {
                        .text => {},
                        .interpolation => |expr| if (interpolationIsInvalid(expr)) {
                            return .{ .component_name = component.name, .err = .SaxInvalidInterpolation, .line = 1, .text = expr.expr };
                        },
                        .json_string_interpolation => |expr| if (interpolationIsInvalid(expr)) {
                            return .{ .component_name = component.name, .err = .SaxInvalidInterpolation, .line = 1, .text = expr.expr };
                        },
                        .json_object_spread => |spread| if (objectSpreadInterpolationIsInvalid(spread.expr)) {
                            return .{ .component_name = component.name, .err = .SaxInvalidInterpolation, .line = 1, .text = spread.expr.expr };
                        },
                    };
                },
            }
        }
        for (node.children) |child| {
            switch (child) {
                .text => |piece| switch (piece) {
                    .text => {},
                    .interpolation => |expr| if (interpolationIsInvalid(expr)) {
                        return .{ .component_name = component.name, .err = .SaxInvalidInterpolation, .line = 1, .text = expr.expr };
                    },
                    .json_string_interpolation => |expr| return .{ .component_name = component.name, .err = .SaxInvalidInterpolation, .line = 1, .text = expr.expr },
                    .json_object_spread => |spread| return .{ .component_name = component.name, .err = .SaxInvalidInterpolation, .line = 1, .text = spread.expr.expr },
                },
                .node_index => {},
            }
        }
    }

    for (component.orphan_lines) |line| {
        if (hasNativeEscape(line.text)) {
            return .{ .component_name = component.name, .err = .SaxInvalidNativeEscape, .line = line.line, .text = line.text };
        }
        if (std.mem.containsAtLeast(u8, line.text, 1, "call @render()")) {
            return .{ .component_name = component.name, .err = .SaxRenderOutsideHandler, .line = line.line, .text = line.text };
        }
        if (std.mem.containsAtLeast(u8, line.text, 1, "store state+")) {
            return .{ .component_name = component.name, .err = .SaxStateWriteFromOutside, .line = line.line, .text = line.text };
        }
    }

    for (component.handlers) |handler| {
        if (!handler.is_ffi_wrapper and hasNativeEscape(handler.body)) {
            return .{ .component_name = component.name, .err = .SaxInvalidNativeEscape, .line = 1, .text = handler.body };
        }
    }
    for (component.lifecycle_hooks) |hook| {
        if (!hook.is_ffi_wrapper and hasNativeEscape(hook.body)) {
            return .{ .component_name = component.name, .err = .SaxInvalidNativeEscape, .line = 1, .text = hook.body };
        }
    }

    return null;
}

fn compileSaxArtifacts(
    allocator: std.mem.Allocator,
    sax_file: []const u8,
    source: []const u8,
    stderr: std.io.AnyWriter,
) !SaxArtifacts {
    var sax_parser = parser.SaxParser.init(allocator, source);
    var program = sax_parser.parse() catch |err| {
        try writeParseError(stderr, sax_file, err);
        return error.SaxCheckFailed;
    };
    defer program.deinit();

    if (program.components.len == 0) {
        try stderr.print("error[SA-REACT-CHECK]: InvalidComponentBody while parsing {s}\n", .{sax_file});
        return error.SaxCheckFailed;
    }

    for (program.components) |component| {
        if (findValidationFailure(allocator, component)) |failure| {
            try writeValidationFailure(stderr, failure);
            return error.SaxCheckFailed;
        }
    }

    const uses_wgpu = sourceUsesWgpu(source);
    const uses_sa3d = sourceUsesSa3d(source);
    var wgpu_airlock_js: ?std.ArrayList(u8) = null;
    errdefer if (wgpu_airlock_js) |*js| js.deinit();
    var sa3d_airlock_js: ?std.ArrayList(u8) = null;
    errdefer if (sa3d_airlock_js) |*js| js.deinit();

    var sa_code = std.ArrayList(u8).init(allocator);
    errdefer sa_code.deinit();
    if (uses_wgpu) {
        var wgpu_support = try loadSidecarSupport(allocator, stderr, wgpu_sidecar);
        defer wgpu_support.prelude.deinit();
        try sa_code.appendSlice(wgpu_support.prelude.items);
        wgpu_airlock_js = wgpu_support.airlock_js;
    }
    if (uses_sa3d) {
        var sa3d_support = try loadSidecarSupport(allocator, stderr, sa3d_sidecar);
        defer sa3d_support.prelude.deinit();
        try sa_code.appendSlice(sa3d_support.prelude.items);
        sa3d_airlock_js = sa3d_support.airlock_js;
    }
    const reachable_components = try reachability.collectReachableComponents(allocator, program.components);
    defer allocator.free(reachable_components);

    for (reachable_components, 0..) |component, idx| {
        var sax_lowerer = try lowerer.SaxLowerer.initWithProgram(allocator, reachable_components, component);
        defer sax_lowerer.deinit();
        sax_lowerer.lower(&sa_code, .{ .emit_shared_decls = idx == 0 }) catch |err| {
            try stderr.print("error[SA-REACT-LOWER]: component {s} failed: {s}\n", .{ component.name, @errorName(err) });
            return err;
        };
        if (idx + 1 < reachable_components.len) try sa_code.writer().writeByte('\n');
    }

    const root_name = try lowercaseName(allocator, program.components[0].name);
    errdefer allocator.free(root_name);
    if (!std.mem.eql(u8, root_name, "app")) {
        try sa_code.writer().print("@export sax_app_init() -> ptr:\nL_ENTRY:\n  ctx = call @sax_{s}_init()\n  return ctx\n\n", .{root_name});
    }

    var airlock_generator = airlock_gen.AirlockGenerator.init(allocator);
    const airlock_js = try airlock_generator.generateAirlockJSWithOptions(.{ .wgpu = uses_wgpu, .sa3d = uses_sa3d });
    errdefer airlock_js.deinit();

    const index_html = try airlock_generator.generateIndexHTML(sourceStem(sax_file), "app.wasm");
    errdefer index_html.deinit();

    return .{
        .component_name = sourceStem(sax_file),
        .root_name = root_name,
        .sa_code = sa_code,
        .shared_sa_code = null,
        .component_sa_codes = null,
        .airlock_js = airlock_js,
        .wgpu_airlock_js = wgpu_airlock_js,
        .sa3d_airlock_js = sa3d_airlock_js,
        .index_html = index_html,
    };
}

fn compileSaxArtifactsSharded(
    allocator: std.mem.Allocator,
    sax_file: []const u8,
    source: []const u8,
    stderr: std.io.AnyWriter,
) !ShardedSaxArtifacts {
    var sax_parser = parser.SaxParser.init(allocator, source);
    var program = sax_parser.parse() catch |err| {
        try writeParseError(stderr, sax_file, err);
        return error.SaxCheckFailed;
    };
    defer program.deinit();

    if (program.components.len == 0) {
        try stderr.print("error[SA-REACT-CHECK]: InvalidComponentBody while parsing {s}\n", .{sax_file});
        return error.SaxCheckFailed;
    }

    for (program.components) |component| {
        if (findValidationFailure(allocator, component)) |failure| {
            try writeValidationFailure(stderr, failure);
            return error.SaxCheckFailed;
        }
    }

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

    for (reachable_components) |component| {
        var component_code = std.ArrayList(u8).init(allocator);
        errdefer component_code.deinit();

        var sax_lowerer = try lowerer.SaxLowerer.initWithProgram(allocator, reachable_components, component);
        defer sax_lowerer.deinit();
        sax_lowerer.lower(&component_code, .{ .shared_decls = .component_externs }) catch |err| {
            try stderr.print("error[SA-REACT-LOWER]: component {s} failed: {s}\n", .{ component.name, @errorName(err) });
            return err;
        };
        try component_sa_codes.append(component_code);
    }

    var airlock_generator = airlock_gen.AirlockGenerator.init(allocator);
    const airlock_js = try airlock_generator.generateAirlockJSWithOptions(.{ .wgpu = false, .sa3d = false });
    errdefer airlock_js.deinit();

    const index_html = try airlock_generator.generateIndexHTML(sourceStem(sax_file), "app.wasm");
    errdefer index_html.deinit();

    return .{
        .shared_sa_code = shared_sa_code,
        .component_sa_codes = component_sa_codes,
        .airlock_js = airlock_js,
        .wgpu_airlock_js = null,
        .sa3d_airlock_js = null,
        .index_html = index_html,
    };
}

fn writeCombinedShardedSa(
    path: []const u8,
    shared_sa_code: []const u8,
    component_sa_codes: []const std.ArrayList(u8),
) !void {
    try ensureParentDir(path);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(shared_sa_code);
    if (shared_sa_code.len != 0 and shared_sa_code[shared_sa_code.len - 1] != '\n') try file.writeAll("\n");
    for (component_sa_codes, 0..) |component_code, idx| {
        if (idx != 0) try file.writeAll("\n");
        try writeComponentSansExternBlock(file.writer(), component_code.items);
    }
}

fn writeComponentSansExternBlock(writer: anytype, text: []const u8) !void {
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
                try writer.writeAll(text[cursor..next_cursor]);
            }
        } else {
            if (line.len == 0 or std.mem.startsWith(u8, line, "@extern ")) {
                cursor = next_cursor;
                continue;
            }
            try writer.writeAll(text[cursor..]);
            return;
        }

        cursor = next_cursor;
    }
}

fn shardedArtifactsToSourceUnits(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    artifacts: *const ShardedSaxArtifacts,
) !std.ArrayList(sax_build.SourceUnit) {
    var units = std.ArrayList(sax_build.SourceUnit).init(allocator);
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

fn verifySaxArtifactsSharded(
    allocator: std.mem.Allocator,
    sax_file: []const u8,
    source: []const u8,
    program: *const parser.SaxProgram,
    stderr: std.io.AnyWriter,
) !void {
    _ = source;
    const reachable_components = try reachability.collectReachableComponents(allocator, program.components);
    defer allocator.free(reachable_components);

    var shared_sa_code = std.ArrayList(u8).init(allocator);
    defer shared_sa_code.deinit();
    var root_lowerer = try lowerer.SaxLowerer.initWithProgram(allocator, reachable_components, program.components[0]);
    defer root_lowerer.deinit();
    try root_lowerer.lower(&shared_sa_code, .{ .shared_decls = .runtime_only, .emit_app_alias = true });

    const shared_verified = try sax_build.compileSourceText(allocator, sax_file, shared_sa_code.items, .{ .jobs = 1 });
    switch (shared_verified) {
        .trap => |report| {
            try sax_build.printTrapReport(stderr, report);
            return error.SaxCheckFailed;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
        },
    }

    for (reachable_components, 0..) |component, idx| {
        var sa_code = std.ArrayList(u8).init(allocator);
        defer sa_code.deinit();

        var sax_lowerer = try lowerer.SaxLowerer.initWithProgram(allocator, reachable_components, component);
        defer sax_lowerer.deinit();
        sax_lowerer.lower(&sa_code, .{ .shared_decls = .component_externs }) catch |err| {
            try stderr.print("error[SA-REACT-LOWER]: component {s} failed: {s}\n", .{ component.name, @errorName(err) });
            return err;
        };

        const verified = try sax_build.compileSourceText(allocator, sax_file, sa_code.items, .{ .jobs = 1 });
        switch (verified) {
            .trap => |report| {
                try sax_build.printTrapReport(stderr, report);
                return error.SaxCheckFailed;
            },
            .ok => |ok| {
                var owned = ok;
                defer owned.deinit(allocator);
            },
        }

        if (idx + 1 < reachable_components.len) try stderr.writeByte('.');
    }
    if (reachable_components.len != 0) try stderr.writeByte('\n');
}

fn parseReactSourceOptions(allocator: std.mem.Allocator, argv: []const []const u8, start: usize) !ReactSourceOptions {
    if (argv.len <= start) return error.MissingSourcePath;

    const source_file = argv[start];
    var out_dir: ?[]const u8 = null;
    var includes = std.ArrayList([]const u8).init(allocator);
    errdefer includes.deinit();

    var i = start + 1;
    while (i < argv.len) : (i += 1) {
        if (std.mem.eql(u8, argv[i], "--out-dir") or std.mem.eql(u8, argv[i], "-o")) {
            if (i + 1 >= argv.len) return error.MissingSourcePath;
            if (out_dir != null) return error.UnexpectedArgument;
            out_dir = argv[i + 1];
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, argv[i], "--include") or std.mem.eql(u8, argv[i], "-I")) {
            if (i + 1 >= argv.len) return error.MissingSourcePath;
            try includes.append(argv[i + 1]);
            i += 1;
            continue;
        }
        return error.UnexpectedArgument;
    }

    return .{
        .source_file = source_file,
        .out_dir = out_dir,
        .includes = try includes.toOwnedSlice(),
    };
}

fn executeSaxCheck(
    ctx: *const plugin_api.Context,
    sax_file: []const u8,
    includes: []const []const u8,
    stdout: std.io.AnyWriter,
    stderr: std.io.AnyWriter,
) !u8 {
    const source = try readComposedSource(ctx.allocator, sax_file, includes, stderr);
    defer ctx.allocator.free(source);
    const uses_wgpu = sourceUsesWgpu(source);
    const uses_sa3d = sourceUsesSa3d(source);

    if (uses_wgpu or uses_sa3d) {
        var artifacts = compileSaxArtifacts(ctx.allocator, sax_file, source, stderr) catch |err| switch (err) {
            error.SaxCheckFailed => return 1,
            else => return err,
        };
        defer artifacts.deinit(ctx.allocator);

        const verified = try sax_build.compileSourceText(ctx.allocator, sax_file, artifacts.sa_code.items, .{});
        switch (verified) {
            .trap => |report| {
                try sax_build.printTrapReport(stderr, report);
                return 1;
            },
            .ok => |ok| {
                var owned = ok;
                defer owned.deinit(ctx.allocator);
            },
        }

        try stdout.print("React check passed: {s}\n", .{sax_file});
        return 0;
    }

    var sax_parser = parser.SaxParser.init(ctx.allocator, source);
    var program = sax_parser.parse() catch |err| {
        try writeParseError(stderr, sax_file, err);
        return 1;
    };
    defer program.deinit();

    if (program.components.len == 0) {
        try stderr.print("error[SA-REACT-CHECK]: InvalidComponentBody while parsing {s}\n", .{sax_file});
        return 1;
    }

    for (program.components) |component| {
        if (findValidationFailure(ctx.allocator, component)) |failure| {
            try writeValidationFailure(stderr, failure);
            return 1;
        }
    }

    verifySaxArtifactsSharded(ctx.allocator, sax_file, source, &program, stderr) catch |err| switch (err) {
        error.SaxCheckFailed => return 1,
        else => return err,
    };

    try stdout.print("React check passed: {s}\n", .{sax_file});
    return 0;
}

fn executeSaxBuild(
    ctx: *const plugin_api.Context,
    sax_file: []const u8,
    includes: []const []const u8,
    out_dir: []const u8,
    stdout: std.io.AnyWriter,
    stderr: std.io.AnyWriter,
) !u8 {
    const source = try readComposedSource(ctx.allocator, sax_file, includes, stderr);
    defer ctx.allocator.free(source);
    const uses_wgpu = sourceUsesWgpu(source);
    const uses_sa3d = sourceUsesSa3d(source);

    const sa_path = try std.fs.path.join(ctx.allocator, &.{ out_dir, "app.sa" });
    defer ctx.allocator.free(sa_path);
    const airlock_path = try std.fs.path.join(ctx.allocator, &.{ out_dir, "airlock.js" });
    defer ctx.allocator.free(airlock_path);
    const wgpu_airlock_path = try std.fs.path.join(ctx.allocator, &.{ out_dir, "wgpu_airlock.js" });
    defer ctx.allocator.free(wgpu_airlock_path);
    const sa3d_airlock_path = try std.fs.path.join(ctx.allocator, &.{ out_dir, "sa3d_airlock.js" });
    defer ctx.allocator.free(sa3d_airlock_path);
    const html_path = try std.fs.path.join(ctx.allocator, &.{ out_dir, "index.html" });
    defer ctx.allocator.free(html_path);
    const wasm_path = try std.fs.path.join(ctx.allocator, &.{ out_dir, "app.wasm" });
    defer ctx.allocator.free(wasm_path);

    if (uses_wgpu or uses_sa3d) {
        var artifacts = compileSaxArtifacts(ctx.allocator, sax_file, source, stderr) catch |err| switch (err) {
            error.SaxCheckFailed => return 1,
            else => return err,
        };
        defer artifacts.deinit(ctx.allocator);

        try writeAllFile(sa_path, artifacts.sa_code.items);

        const build_code = try sax_build.buildBrowserWasmFromSourceText(
            ctx.allocator,
            sa_path,
            artifacts.sa_code.items,
            wasm_path,
            false,
            .release_small,
            .{ .jobs = 1, .dce = .full },
            stderr,
        );
        if (build_code != 0) return build_code;

        try writeAllFile(airlock_path, artifacts.airlock_js.items);
        if (artifacts.wgpu_airlock_js) |*wgpu_js| {
            try writeAllFile(wgpu_airlock_path, wgpu_js.items);
        }
        if (artifacts.sa3d_airlock_js) |*sa3d_js| {
            try writeAllFile(sa3d_airlock_path, sa3d_js.items);
        }
        try writeAllFile(html_path, artifacts.index_html.items);

        try stdout.print("React build successful\n", .{});
        try stdout.print("  app.sa: {s}\n", .{sa_path});
        try stdout.print("  app.wasm: {s}\n", .{wasm_path});
        try stdout.print("  airlock.js: {s}\n", .{airlock_path});
        if (artifacts.wgpu_airlock_js != null) try stdout.print("  wgpu_airlock.js: {s}\n", .{wgpu_airlock_path});
        if (artifacts.sa3d_airlock_js != null) try stdout.print("  sa3d_airlock.js: {s}\n", .{sa3d_airlock_path});
        try stdout.print("  index.html: {s}\n", .{html_path});
        return 0;
    }

    var artifacts = compileSaxArtifactsSharded(ctx.allocator, sax_file, source, stderr) catch |err| switch (err) {
        error.SaxCheckFailed => return 1,
        else => return err,
    };
    defer artifacts.deinit(ctx.allocator);

    try writeCombinedShardedSa(sa_path, artifacts.shared_sa_code.items, artifacts.component_sa_codes.items);

    var source_units = try shardedArtifactsToSourceUnits(ctx.allocator, sax_file, &artifacts);
    defer {
        for (source_units.items) |unit| ctx.allocator.free(unit.logical_name);
        source_units.deinit();
    }

    const build_code = try sax_build.buildBrowserWasmFromSourceUnits(
        ctx.allocator,
        source_units.items,
        wasm_path,
        false,
        .release_small,
        .{ .jobs = 1, .dce = .full },
        stderr,
    );
    if (build_code != 0) return build_code;

    try writeAllFile(airlock_path, artifacts.airlock_js.items);
    try writeAllFile(html_path, artifacts.index_html.items);

    try stdout.print("React build successful\n", .{});
    try stdout.print("  app.sa: {s}\n", .{sa_path});
    try stdout.print("  app.wasm: {s}\n", .{wasm_path});
    try stdout.print("  airlock.js: {s}\n", .{airlock_path});
    try stdout.print("  index.html: {s}\n", .{html_path});
    return 0;
}

fn executeSaxNew(ctx: *const plugin_api.Context, project_name: []const u8, stdout: std.io.AnyWriter) !u8 {
    try std.fs.cwd().makePath(project_name);

    const sax_template =
        \\<Component name="App">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <div class="app">
        \\    <h1>Hello React</h1>
        \\    <p>Count: {count}</p>
        \\    <button onclick={^increment}>+1</button>
        \\  </div>
        \\  @increment:
        \\  L_ENTRY:
        \\    count = load state+App_count as i64
        \\    count = add count, 1
        \\    store state+App_count, count as i64
        \\    call @render()
        \\    ret
        \\  !count
        \\</Component>
        \\
    ;

    const sax_path = try std.fs.path.join(ctx.allocator, &.{ project_name, "app.sax" });
    defer ctx.allocator.free(sax_path);
    try writeAllFile(sax_path, sax_template);

    const readme_path = try std.fs.path.join(ctx.allocator, &.{ project_name, "README.md" });
    defer ctx.allocator.free(readme_path);
    const readme = try std.fmt.allocPrint(ctx.allocator,
        \\# {s}
        \\
        \\React-on-SAX project scaffold.
        \\
        \\```bash
        \\sa react check app.sax
        \\sa react build app.sax
        \\```
        \\
    , .{project_name});
    defer ctx.allocator.free(readme);
    try writeAllFile(readme_path, readme);

    const package_path = try std.fs.path.join(ctx.allocator, &.{ project_name, "package.json" });
    defer ctx.allocator.free(package_path);
    const package_json = try std.fmt.allocPrint(ctx.allocator,
        \\{{
        \\  "name": "{s}",
        \\  "private": true,
        \\  "type": "module",
        \\  "scripts": {{
        \\    "check": "sa react check app.sax",
        \\    "build": "sa react build app.sax",
        \\    "dev": "sa react dev app.sax"
        \\  }}
        \\}}
        \\
    , .{project_name});
    defer ctx.allocator.free(package_json);
    try writeAllFile(package_path, package_json);

    try stdout.print("React project created: {s}\n", .{project_name});
    try stdout.print("  app.sax: {s}\n", .{sax_path});
    try stdout.print("  README.md: {s}\n", .{readme_path});
    try stdout.print("  package.json: {s}\n", .{package_path});
    return 0;
}

fn runSaxCommandImpl(ctx: *const plugin_api.Context, argv: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) anyerror!?u8 {
    if (argv.len < 2) return null;
    if (!std.mem.eql(u8, argv[1], "react")) return null;
    if (argv.len < 3) return error.MissingSourcePath;

    const sub = argv[2];
    if (std.mem.eql(u8, sub, "build")) {
        var options = try parseReactSourceOptions(ctx.allocator, argv, 3);
        defer options.deinit(ctx.allocator);
        const out_dir = options.out_dir orelse "dist";
        return try executeSaxBuild(ctx, options.source_file, options.includes, out_dir, stdout, stderr);
    }
    if (std.mem.eql(u8, sub, "check")) {
        var options = try parseReactSourceOptions(ctx.allocator, argv, 3);
        defer options.deinit(ctx.allocator);
        if (options.out_dir != null) return error.UnexpectedArgument;
        return try executeSaxCheck(ctx, options.source_file, options.includes, stdout, stderr);
    }
    if (std.mem.eql(u8, sub, "dev")) {
        var options = try parseReactSourceOptions(ctx.allocator, argv, 3);
        defer options.deinit(ctx.allocator);
        const out_dir = options.out_dir orelse "dist";
        const code = try executeSaxBuild(ctx, options.source_file, options.includes, out_dir, stdout, stderr);
        if (code == 0) try stdout.print("React dev artifacts refreshed in {s}\n", .{out_dir});
        return code;
    }
    if (std.mem.eql(u8, sub, "new")) {
        if (argv.len != 4) return if (argv.len < 4) error.MissingSourcePath else error.UnexpectedArgument;
        return try executeSaxNew(ctx, argv[3], stdout);
    }
    return error.UnknownCommand;
}

fn anyWriterFromHostStream(stream: plugin_api.HostStream, storage: *plugin_api.HostStream) std.io.AnyWriter {
    storage.* = stream;
    return .{ .context = storage, .writeFn = struct {
        fn write(ctx: *const anyopaque, bytes: []const u8) anyerror!usize {
            const hs = @as(*const plugin_api.HostStream, @ptrCast(@alignCast(ctx)));
            const write_all = hs.write_all orelse return error.WriteFailed;
            if (write_all(hs.ctx, bytes.ptr, bytes.len) != @intFromEnum(plugin_api.AbiStatus.ok)) return error.WriteFailed;
            return bytes.len;
        }
    }.write };
}

fn runSaxCommandAbi(ctx: *const plugin_api.Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: plugin_api.HostStream, stderr: plugin_api.HostStream, out_code: *u8) callconv(.c) u32 {
    out_code.* = 0;
    const allocator = std.heap.page_allocator;
    var local_ctx = ctx.*;
    local_ctx.allocator = allocator;
    const args = cArgvToSlice(argv, argv_len, allocator) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    defer allocator.free(args);

    var stdout_storage = stdout;
    var stderr_storage = stderr;
    const stdout_writer = anyWriterFromHostStream(stdout, &stdout_storage);
    const stderr_writer = anyWriterFromHostStream(stderr, &stderr_storage);

    const result = runSaxCommandImpl(&local_ctx, args, stdout_writer, stderr_writer) catch |err| {
        if (!isReactCliError(err)) return @intFromEnum(plugin_api.AbiStatus.failed);
        writeSaxCliError(stderr_writer, args, err) catch return @intFromEnum(plugin_api.AbiStatus.failed);
        out_code.* = reactCliExitCode(err);
        return @intFromEnum(plugin_api.AbiStatus.ok);
    };
    if (result) |code| {
        out_code.* = code;
        return @intFromEnum(plugin_api.AbiStatus.ok);
    }
    return @intFromEnum(plugin_api.AbiStatus.unknown_command);
}

const descriptor = plugin_api.PluginDescriptor{
    .abi_version = plugin_api.abi_version,
    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_api.PluginDescriptor))),
    .name = "react",
    .init = null,
    .prebuild = null,
    .postbuild = null,
    .handle_command = runSaxCommandAbi,
    .skills_ptr = skills[0..].ptr,
    .skills_len = skills.len,
};

pub export const saasm_plugin_descriptor_v1: plugin_api.PluginDescriptor = descriptor;
pub export fn saasm_plugin_descriptor_v1_fn(out: *plugin_api.PluginDescriptor) callconv(.c) void {
    out.* = descriptor;
}

const CaptureStream = struct {
    buffer: *std.ArrayList(u8),
};

fn captureWriteAll(ctx: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) u32 {
    const stream = @as(*CaptureStream, @ptrCast(@alignCast(ctx orelse return @intFromEnum(plugin_api.AbiStatus.failed))));
    stream.buffer.appendSlice(bytes[0..len]) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    return @intFromEnum(plugin_api.AbiStatus.ok);
}

fn captureHostStream(ctx: *CaptureStream) plugin_api.HostStream {
    return .{ .ctx = ctx, .write_all = captureWriteAll };
}

fn dupeZArgs(allocator: std.mem.Allocator, argv: []const []const u8) ![][*:0]const u8 {
    var out = try allocator.alloc([*:0]const u8, argv.len);
    errdefer allocator.free(out);
    var copied: usize = 0;
    errdefer {
        for (out[0..copied]) |arg| allocator.free(std.mem.sliceTo(arg, 0));
    }
    for (argv, 0..) |arg, idx| {
        out[idx] = try allocator.dupeZ(u8, arg);
        copied += 1;
    }
    return out;
}

fn freeZArgs(allocator: std.mem.Allocator, argv: [][*:0]const u8) void {
    for (argv) |arg| allocator.free(std.mem.sliceTo(arg, 0));
    allocator.free(argv);
}

fn invokeForTest(argv: []const []const u8, stdout_buffer: *std.ArrayList(u8), stderr_buffer: *std.ArrayList(u8), allocator: std.mem.Allocator) !u8 {
    var ctx = plugin_api.Context{ .allocator = allocator };
    var stdout_ctx = CaptureStream{ .buffer = stdout_buffer };
    var stderr_ctx = CaptureStream{ .buffer = stderr_buffer };
    const c_argv = try dupeZArgs(allocator, argv);
    defer freeZArgs(allocator, c_argv);
    var out_code: u8 = 255;
    const status = runSaxCommandAbi(&ctx, c_argv.ptr, c_argv.len, captureHostStream(&stdout_ctx), captureHostStream(&stderr_ctx), &out_code);
    try std.testing.expectEqual(@as(u32, @intFromEnum(plugin_api.AbiStatus.ok)), status);
    return out_code;
}

const valid_counter_sax =
    \\<Component name="Counter">
    \\  <state>
    \\    count = 0
    \\  </state>
    \\  <div class="counter">
    \\    <p>{count}</p>
    \\    <button onclick={^inc}>+1</button>
    \\  </div>
    \\  @inc:
    \\  L_ENTRY:
    \\    count = load state+Counter_count as i64
    \\    count = add count, 1
    \\    store state+Counter_count, count as i64
    \\    call @render()
    \\    ret
    \\  !count
    \\</Component>
    \\
;

fn expectSaxCheckFailure(source: []const u8, file_name: []const u8, expected_error: []const u8) !void {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeAllFile(file_name, source);
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const code = try invokeForTest(&.{ "sa", "react", "check", file_name }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buf.items, 1, expected_error));
}

fn expectSaxCliFailure(argv: []const []const u8, expected_code: u8, expected_error: []const u8) !void {
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const code = try invokeForTest(argv, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(expected_code, code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buf.items, 1, expected_error));
}

fn expectNoNonWhitespaceStderr(stderr: []const u8) !void {
    for (stderr) |byte| {
        switch (byte) {
            ' ', '\t', '\r', '\n', '.' => {},
            else => return error.TestExpectedEqual,
        }
    }
}

test "react plugin exports runtime descriptor" {
    try std.testing.expectEqualStrings("react", std.mem.span(descriptor.name));
    try std.testing.expectEqual(@as(usize, 1), descriptor.skills_len);
}

test "react plugin abi maps missing build file to usage exit code" {
    try expectSaxCliFailure(&.{ "sa", "react", "build" }, 2, "error[SA-REACT-CLI]: missing required React operand");
}

test "react plugin abi maps unknown subcommands to usage exit code" {
    try expectSaxCliFailure(&.{ "sa", "react", "unknown" }, 2, "error[SA-REACT-CLI]: unknown React subcommand");
}

test "react plugin abi maps missing source files to io exit code" {
    try expectSaxCliFailure(&.{ "sa", "react", "check", "missing.sax" }, 3, "error[SA-REACT-CLI]: React file or directory not found");
}

test "react plugin check parses and lowers a real component" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeAllFile("counter.sax", valid_counter_sax);
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const code = try invokeForTest(&.{ "sa", "react", "check", "counter.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().openFile("dist/app.sa", .{}));
}

test "react plugin build emits frontend artifacts from real sax source" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeAllFile("counter.sax", valid_counter_sax);
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const code = try invokeForTest(&.{ "sa", "react", "build", "counter.sax", "--out-dir", "public" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React build successful"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, stdout_buf.items, 1, "sax build:"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);

    const sa = try std.fs.cwd().readFileAlloc(std.testing.allocator, "public/app.sa", 2 * 1024 * 1024);
    defer std.testing.allocator.free(sa);
    try std.testing.expect(std.mem.containsAtLeast(u8, sa, 1, "@export sax_counter_init()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sa, 1, "@export sax_app_init()"));

    const airlock = try std.fs.cwd().readFileAlloc(std.testing.allocator, "public/airlock.js", 2 * 1024 * 1024);
    defer std.testing.allocator.free(airlock);
    try std.testing.expect(std.mem.containsAtLeast(u8, airlock, 1, "export const sax_airlock"));
    try std.testing.expect(std.mem.containsAtLeast(u8, airlock, 1, "const SAX_WGPU_REQUIRED = false;"));
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().openFile("public/wgpu_airlock.js", .{}));

    const html = try std.fs.cwd().readFileAlloc(std.testing.allocator, "public/index.html", 2 * 1024 * 1024);
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.containsAtLeast(u8, html, 1, "Content-Security-Policy"));

    const wasm = try std.fs.cwd().readFileAlloc(std.testing.allocator, "public/app.wasm", 1024);
    defer std.testing.allocator.free(wasm);
    try std.testing.expect(wasm.len > 8);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 'a', 's', 'm', 0x01, 0x00, 0x00, 0x00 }, wasm[0..8]);
}

test "react plugin composes included sax component sources" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const app_source =
        \\<Component name="App">
        \\  <div>
        \\    <LibraryButton />
        \\  </div>
        \\</Component>
        \\
    ;
    const library_source =
        \\<Component name="LibraryButton">
        \\  <button type="button">Library</button>
        \\</Component>
        \\
    ;

    try std.fs.cwd().makePath("lib");
    try writeAllFile("app.sax", app_source);
    try writeAllFile("lib/components.sax", library_source);
    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const check_code = try invokeForTest(&.{ "sa", "react", "check", "app.sax", "--include", "lib/components.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), check_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);

    stdout_buf.clearRetainingCapacity();
    stderr_buf.clearRetainingCapacity();
    const build_code = try invokeForTest(&.{ "sa", "react", "build", "app.sax", "--include", "lib/components.sax", "--out-dir", "public" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), build_code);
    try expectNoNonWhitespaceStderr(stderr_buf.items);

    const sa = try std.fs.cwd().readFileAlloc(std.testing.allocator, "public/app.sa", 2 * 1024 * 1024);
    defer std.testing.allocator.free(sa);
    try std.testing.expect(std.mem.containsAtLeast(u8, sa, 1, "@export sax_app_init()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, sa, 1, "@export sax_librarybutton_init()"));
}

test "react plugin resolves includes from loaded plugin share dirs" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const app_source =
        \\<Component name="App">
        \\  <div>
        \\    <LibraryButton />
        \\  </div>
        \\</Component>
        \\
    ;
    const library_source =
        \\<Component name="LibraryButton">
        \\  <button type="button">Shared</button>
        \\</Component>
        \\
    ;

    try std.fs.cwd().makePath("fake/zig-out/lib");
    try std.fs.cwd().makePath("fake/zig-out/share/mui");
    try writeAllFile("app.sax", app_source);
    try writeAllFile("fake/zig-out/share/mui/material.sax", library_source);

    try std.testing.expectEqual(@as(c_int, 0), setenv("SA_PLUGINS_PATH", "fake/zig-out/lib/libmui.so", 1));
    defer _ = unsetenv("SA_PLUGINS_PATH");

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const check_code = try invokeForTest(&.{ "sa", "react", "check", "app.sax", "--include", "mui/material.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), check_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin resolves includes relative to cwd before plugin installs" {
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

test "react plugin check reports state leaks" {
    const leak_source =
        \\<Component name="Counter">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <p>{count}</p>
        \\</Component>
        \\
    ;
    try expectSaxCheckFailure(leak_source, "leak.sax", "SaxStateLeak");
}

test "react plugin check reports event handler escapes" {
    const escape_source =
        \\<Component name="Counter">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <button onclick={^missing}>+1</button>
        \\  !count
        \\</Component>
        \\
    ;
    try expectSaxCheckFailure(escape_source, "event_escape.sax", "SaxEventEscape");
}

test "react plugin check rejects affine operators in interpolation" {
    const invalid_source =
        \\<Component name="Counter">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <p>{count + ^x}</p>
        \\  !count
        \\</Component>
        \\
    ;
    try expectSaxCheckFailure(invalid_source, "invalid_interpolation.sax", "SaxInvalidInterpolation");
}

test "react plugin check accepts negated logical object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ...(!active && { idle: true }), count: 1 }} />
        \\  !active
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "negated_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "negated_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check accepts logical or object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ...(active || { idle: true }), count: 1 }} />
        \\  !active
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "logical_or_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "logical_or_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check accepts negated logical or object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ ...(!active || { active_branch: true }), count: 1 }} />
        \\  !active
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "negated_logical_or_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "negated_logical_or_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check accepts nested dynamic object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...nested_extra, current: 1 } }} />
        \\  !nested_extra !nested_extra_len
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "nested_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "nested_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check accepts nested ptr ternary object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...(active ? nested_extra : { idle_nested_branch: true }), ...(active ? nested_extra : object_branch), ...(active ? nested_extra : null), ...(active ? { active_nested_branch: true } : null), ...(active && { active_nested_and: true }), ...(!active && { idle_nested_and: true }), ...(active || { idle_nested_or: true }), ...(!active || { active_nested_or: true }), current: 1 } }} />
        \\  !active !nested_extra !nested_extra_len !object_branch !object_branch_len
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "nested_ptr_ternary_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "nested_ptr_ternary_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check accepts nested logical or ptr object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\    object_branch = alloc 64
        \\    object_branch_len = 0
        \\  </state>
        \\  <Widget config={{ nested: { size: 2, ...(active || object_branch), ...(!active || object_branch), current: 1 } }} />
        \\  !active !object_branch !object_branch_len
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "nested_logical_or_ptr_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "nested_logical_or_ptr_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check accepts array item dynamic object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ items: [{ size: 1, ...nested_extra, current: 1 }] }} />
        \\  !nested_extra !nested_extra_len
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "array_item_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "array_item_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check accepts leading array item dynamic object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    nested_extra = alloc 64
        \\    nested_extra_len = 0
        \\  </state>
        \\  <Widget config={{ leading_items: [{ ...nested_extra, current: 1 }] }} />
        \\  !nested_extra !nested_extra_len
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "leading_array_item_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "leading_array_item_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check accepts leading array item conditional object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ leading_conditional_items: [{ ...(!active && { idle_leading_item: true }), current: 1 }] }} />
        \\  !active
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "leading_array_item_conditional_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "leading_array_item_conditional_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check accepts leading array item ternary null branch object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ leading_null_items: [{ ...(active ? { active_leading_branch: true } : null), current: 1 }] }} />
        \\  !active
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "leading_array_item_ternary_null_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "leading_array_item_ternary_null_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check accepts leading array item logical or object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ leading_or_items: [{ ...(active || { idle_leading_or: true }), current: 1 }], leading_negated_or_items: [{ ...(!active || { active_leading_or: true }), current: 1 }] }} />
        \\  !active
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "leading_array_item_logical_or_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "leading_array_item_logical_or_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check accepts array item conditional object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ items: [{ size: 1, ...(!active && { idle_item: true }), ...(active && { active_item: true }), current: 1 }] }} />
        \\  !active
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "array_item_conditional_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "array_item_conditional_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check accepts array item ternary null branch object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ items: [{ size: 1, ...(active ? { active_item_branch: true } : null), current: 1 }] }} />
        \\  !active
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "array_item_ternary_null_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "array_item_ternary_null_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check accepts array item logical or object spreads" {
    const valid_source =
        \\<Component name="App">
        \\  <state>
        \\    active = 0 as i1
        \\  </state>
        \\  <Widget config={{ items: [{ size: 1, ...(active || { idle_item_or: true }), ...(!active || { active_item_or: true }), current: 1 }] }} />
        \\  !active
        \\</Component>
        \\<Component name="Widget">
        \\  <state>
        \\    config = alloc 64
        \\    config_len = 0
        \\  </state>
        \\  <pre>{config}</pre>
        \\  !config !config_len
        \\</Component>
        \\
    ;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "array_item_logical_or_spread.sax", .data = valid_source });

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();
    const code = try invokeForTest(&.{ "sa", "react", "check", "array_item_logical_or_spread.sax" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React check passed"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);
}

test "react plugin check rejects render calls outside handlers" {
    const invalid_source =
        \\<Component name="Counter">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <p>{count}</p>
        \\  !count
        \\  call @render()
        \\</Component>
        \\
    ;
    try expectSaxCheckFailure(invalid_source, "render_outside_handler.sax", "SaxRenderOutsideHandler");
}

test "react plugin check rejects state writes outside component handlers" {
    const invalid_source =
        \\<Component name="Counter">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <p>{count}</p>
        \\  !count
        \\  store state+Counter_count, 1 as i64
        \\</Component>
        \\
    ;
    try expectSaxCheckFailure(invalid_source, "state_write_outside.sax", "SaxStateWriteFromOutside");
}

test "react plugin check rejects dangerous DOM tags" {
    const dangerous_tag_source =
        \\<Component name="Counter">
        \\  <script>bad</script>
        \\</Component>
        \\
    ;
    try expectSaxCheckFailure(dangerous_tag_source, "dangerous_tag.sax", "SaxUnknownTag");
}

test "react plugin check rejects unknown DOM events" {
    const unknown_event_source =
        \\<Component name="Counter">
        \\  <state>
        \\    count = 0
        \\  </state>
        \\  <button onhover={^inc}>+1</button>
        \\  @inc:
        \\  L_ENTRY:
        \\    ret
        \\  !count
        \\</Component>
        \\
    ;
    try expectSaxCheckFailure(unknown_event_source, "unknown_event.sax", "SaxUnknownEvent");
}

test "react plugin check rejects DOM attrs outside the whitelist" {
    const unsafe_source =
        \\<Component name="Unsafe">
        \\  <div innerHTML="<img src=x>"></div>
        \\</Component>
        \\
    ;
    try expectSaxCheckFailure(unsafe_source, "unsafe_attr.sax", "SaxInvalidAttribute");
}

test "react plugin new creates a usable project scaffold" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const code = try invokeForTest(&.{ "sa", "react", "new", "demo" }, &stdout_buf, &stderr_buf, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buf.items, 1, "React project created"));
    try expectNoNonWhitespaceStderr(stderr_buf.items);

    const app = try std.fs.cwd().readFileAlloc(std.testing.allocator, "demo/app.sax", 1024 * 1024);
    defer std.testing.allocator.free(app);
    try std.testing.expect(std.mem.containsAtLeast(u8, app, 1, "<Component name=\"App\">"));

    const package_json = try std.fs.cwd().readFileAlloc(std.testing.allocator, "demo/package.json", 1024 * 1024);
    defer std.testing.allocator.free(package_json);
    try std.testing.expect(std.mem.containsAtLeast(u8, package_json, 1, "\"build\": \"sa react build app.sax\""));
}
