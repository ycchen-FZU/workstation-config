[CmdletBinding()]
param(
    [string]$PackageRoot = "$env:APPDATA\npm\node_modules\@waishnav\devspace",
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$SupportedPackageName = '@waishnav/devspace'
$SupportedVersion = '1.0.7'

$OfficialHashes = [ordered]@{
    'dist/cli.js' = '0a0b52b744eca7bfa58bac205c92fe68c2f5bbd88acd89bab0cd9f5ad91cd6c8'
    'dist/config.js' = '92c8d6c3819fc08e521c48d611be13974c7a7d86114664132917ea32b572d3dc'
    'dist/db/migrations.js' = '9cca65495fef9212eb605a9a02e833d53d62eada14ac8369b418888da55be54d'
    'dist/db/schema.js' = '5a123a2d87ceae8a38ae6cfa4d5cd54b46e6051f11aaac70721a23a97fe85d7f'
    'dist/server.js' = '42d340924421182eea7f2580f96c8d1d5aae459061a6a90804e6900905ef2d72'
    'dist/user-config.js' = 'e7b501d42c9d2103964691f70dc8b493fbf58adbf534fb1d1f805b837c8362da'
    'dist/oauth-provider.js' = '90ff3fd116735e98af5751de1065538964f6eaae913171223e8e19337b9831b8'
    'dist/oauth-store.js' = '3ece5fe3e3e4f6d24b33a4c0863aed6d5fcce3cbd5f3b0c45198c857174e7b48'
}

$PatchedHashes = [ordered]@{
    'dist/cli.js' = '627aee5c8e3848819a6e1f78aee75631b46c6c4bf8a6cd2c43dffde7955ae2bc'
    'dist/config.js' = '5a8c28337c25647decee959e4249bea30650733488b0a4c298276217e6945683'
    'dist/db/migrations.js' = '175e9ac623d9f5cd1c50381ab39f529cd057c4ed1b3a03392f63a6820239c139'
    'dist/db/schema.js' = '0b84701e0978f20348e690474770355ac4c1255894fc6453d7eb08ab88c527fc'
    'dist/server.js' = 'f5a5c3321040b6e6e3adcf10aa19129624322f483eae5931735f1edff761d980'
    'dist/user-config.js' = 'a81fbc4bf30f7fad522f49a505360a44a8ce1e9989d8017e681d1a087b98ca74'
    'dist/remote-auth.js' = '56003a3fb143a72f1073c55bee841c6628779a465306808b9c26636c2e27063e'
}

function Get-Hash {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Text {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.File]::ReadAllText($Path)
}

function Set-Text {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Replace-Exact {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$New,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $first = $Text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Missing expected block: $Label" }
    $second = $Text.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
    if ($second -ge 0) { throw "Expected block occurs more than once: $Label" }
    return $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

function Replace-Range {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$StartMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Replacement,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Missing start marker: $Label" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { throw "Missing end marker: $Label" }
    return $Text.Substring(0, $start) + $Replacement + $Text.Substring($end)
}

function Assert-Package {
    $packageJsonPath = Join-Path $PackageRoot 'package.json'
    if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
        throw "package.json not found: $packageJsonPath"
    }
    $package = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
    if ($package.name -ne $SupportedPackageName -or $package.version -ne $SupportedVersion) {
        throw "Unsupported DevSpace package: $($package.name)@$($package.version). Supported: $SupportedPackageName@$SupportedVersion."
    }
}

function Test-PatchedState {
    foreach ($entry in $PatchedHashes.GetEnumerator()) {
        $path = Join-Path $PackageRoot $entry.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
        if ((Get-Hash $path) -ne $entry.Value) { return $false }
    }
    if (Test-Path -LiteralPath (Join-Path $PackageRoot 'dist/oauth-provider.js')) { return $false }
    if (Test-Path -LiteralPath (Join-Path $PackageRoot 'dist/oauth-store.js')) { return $false }
    return $true
}

function Assert-OfficialState {
    foreach ($entry in $OfficialHashes.GetEnumerator()) {
        $path = Join-Path $PackageRoot $entry.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required official file not found: $path"
        }
        $actual = Get-Hash $path
        if ($actual -ne $entry.Value) {
            throw "Unexpected file hash for $($entry.Key): $actual. Refusing to patch unknown state."
        }
    }
    $remoteAuthPath = Join-Path $PackageRoot 'dist/remote-auth.js'
    if (Test-Path -LiteralPath $remoteAuthPath) {
        throw "Unexpected file already exists: $remoteAuthPath"
    }
}

Assert-Package
if (Test-PatchedState) {
    Write-Output "DevSpace Authelia auth patch is already applied: $PackageRoot"
    exit 0
}
Assert-OfficialState

if ($CheckOnly) {
    Write-Output "DevSpace is in the supported official OAuth state and can be patched safely: $PackageRoot"
    exit 0
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $PackageRoot "backup-authelia-auth-$timestamp"
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
foreach ($entry in $OfficialHashes.GetEnumerator()) {
    $source = Join-Path $PackageRoot $entry.Key
    $target = Join-Path $backupRoot $entry.Key
    New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($target)) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target
}

try {
    $cliPath = Join-Path $PackageRoot 'dist/cli.js'
    $text = Get-Text $cliPath
    $text = Replace-Exact $text 'import { ensureDevspaceDefaultSkills, generateOwnerToken, loadDevspaceFiles, resolveSubagentsFlag, writeDevspaceAuth, writeDevspaceConfig, } from "./user-config.js";' 'import { ensureDevspaceDefaultSkills, loadDevspaceFiles, resolveSubagentsFlag, writeDevspaceConfig, } from "./user-config.js";' 'cli import'
    $ensureConfiguredBlock = @'
async function ensureConfigured() {
    const files = loadDevspaceFiles();
    if (files.configExists)
        return;
    if (!input.isTTY || !output.isTTY) {
        throw new Error([
            "DevSpace is not configured and this terminal is non-interactive.",
            "",
            "Run:",
            "  devspace init",
        ].join("\n"));
    }
    await runInit({ force: false });
}
'@
    $ensureConfiguredBlock += "`n"
    $text = Replace-Range -Text $text -StartMarker 'async function ensureConfigured() {' -EndMarker 'async function runInit({ force }) {' -Replacement $ensureConfiguredBlock -Label 'cli ensureConfigured'
    $text = Replace-Exact $text '    if (!force && files.configExists && files.authExists) {' '    if (!force && files.configExists) {' 'cli init condition'
    $authCreationBlock = @'
        const auth = {
            ownerToken: files.auth.ownerToken ?? generateOwnerToken(),
        };
'@
    $authCreationBlock += "`n"
    $text = Replace-Exact -Text $text -Old $authCreationBlock -New '' -Label 'cli auth creation'
    $oldAuthWrite = '        const authPath = writeDevspaceAuth(auth);' + "`n"
    $text = Replace-Exact -Text $text -Old $oldAuthWrite -New '' -Label 'cli auth write'
    $oldAuthNoteLine = '            `Auth: ${authPath}`,' + "`n"
    $text = Replace-Exact -Text $text -Old $oldAuthNoteLine -New '' -Label 'cli auth note line'
    $text = Replace-Exact $text '            ...(publicBaseUrl ? [`Public MCP URL: ${publicBaseUrl}/mcp`] : []),' '            ...(publicBaseUrl ? [`Public MCP URL: ${publicBaseUrl}`] : []),' 'cli public url'
    $ownerPasswordBlock = @'
        prompts.note([
            `Owner password: ${auth.ownerToken}`,
            "Use this when ChatGPT or Claude asks you to approve DevSpace access.",
            `Stored at: ${authPath}`,
        ].join("\n"), "Owner password");
'@
    $ownerPasswordBlock += "`n"
    $text = Replace-Exact -Text $text -Old $ownerPasswordBlock -New '' -Label 'cli owner password note'
    $text = Replace-Exact $text '        console.log("auth: Owner password approval required");' '        console.log("auth: Authelia OAuth Resource Server");' 'cli auth log'
    $oldDoctorAuthFile = '    console.log(`Auth file: ${files.authExists ? files.authPath : "missing"}`);' + "`n"
    $text = Replace-Exact -Text $text -Old $oldDoctorAuthFile -New '' -Label 'cli doctor auth file'
    $doctorOAuthBlock = @'
        console.log(`Public MCP URL: ${config.publicBaseUrl}`);
        console.log(`OAuth issuer: ${config.oauth.issuer}`);
        console.log(`OAuth resource: ${config.oauth.resourceUrl}`);
        console.log(`OAuth JWKS: ${config.oauth.jwksUri}`);
'@
    $text = Replace-Exact -Text $text -Old '        console.log(`Public MCP URL: ${new URL("/mcp", config.publicBaseUrl).toString()}`);' -New $doctorOAuthBlock -Label 'cli doctor oauth'
    $text = Replace-Exact $text '        "  devspace init            Create or update ~/.devspace/config.json and auth.json",' '        "  devspace init            Create or update ~/.devspace/config.json",' 'cli help'
    Set-Text $cliPath $text

    $configPath = Join-Path $PackageRoot 'dist/config.js'
    $text = Get-Text $configPath
    $text = Replace-Exact -Text $text -Old "const DEFAULT_OAUTH_ACCESS_TOKEN_TTL_SECONDS = 60 * 60;`n" -New '' -Label 'config access ttl'
    $text = Replace-Exact -Text $text -Old "const DEFAULT_OAUTH_REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60;`n" -New '' -Label 'config refresh ttl'
    $oauthBlock = @'
function parseOAuthUrl(value, name, trailingSlash = false) {
    try {
        const parsed = new URL(value);
        parsed.hash = "";
        parsed.search = "";
        if (trailingSlash) {
            parsed.pathname = `${parsed.pathname.replace(/\/+$/, "")}/`;
            return parsed.toString();
        }
        return parsed.toString().replace(/\/$/, "");
    }
    catch {
        throw new Error(`Invalid ${name}: ${value}`);
    }
}
function parseOAuthConfig(env, fileConfig = {}) {
    const configuredScopes = Array.isArray(fileConfig.scopes)
        ? fileConfig.scopes.join(",")
        : fileConfig.scopes;
    const issuer = parseOAuthUrl(
        env.DEVSPACE_OAUTH_ISSUER ?? fileConfig.issuer ?? "https://auth.chen-group.cn",
        "DEVSPACE_OAUTH_ISSUER",
    );
    const resourceUrl = parseOAuthUrl(
        env.DEVSPACE_OAUTH_RESOURCE_URL ?? fileConfig.resourceUrl ?? "https://devspace.chen-group.cn/",
        "DEVSPACE_OAUTH_RESOURCE_URL",
        true,
    );
    const jwksUri = parseOAuthUrl(
        env.DEVSPACE_OAUTH_JWKS_URI ?? fileConfig.jwksUri ?? `${issuer}/jwks.json`,
        "DEVSPACE_OAUTH_JWKS_URI",
    );
    return {
        issuer,
        resourceUrl,
        jwksUri,
        scopes: parseStringList(env.DEVSPACE_OAUTH_SCOPES ?? configuredScopes, []),
    };
}
'@
    $oauthBlock += "`n"
    $text = Replace-Range $text 'function parseRequiredSecret(value, name) {' 'function defaultStateDir() {' $oauthBlock 'config oauth block'
    $text = Replace-Exact $text '        oauth: parseOAuthConfig(env, files.auth.ownerToken),' '        oauth: parseOAuthConfig(env, files.config.oauth),' 'config oauth load'
    Set-Text $configPath $text

    $migrationPath = Join-Path $PackageRoot 'dist/db/migrations.js'
    $text = Get-Text $migrationPath
    $oauthMigrationRegistration = @'
    {
        version: 2,
        name: "oauth-state",
        up: migrateOAuthState,
    },
'@
    $oauthMigrationRegistration += "`n"
    $text = Replace-Exact -Text $text -Old $oauthMigrationRegistration -New '' -Label 'oauth migration registration'
    $text = Replace-Range -Text $text -StartMarker 'function migrateOAuthState(sqlite) {' -EndMarker 'function migrateLocalAgentSessions(sqlite) {' -Replacement '' -Label 'oauth migration function'
    Set-Text $migrationPath $text

    $schemaPath = Join-Path $PackageRoot 'dist/db/schema.js'
    $text = Get-Text $schemaPath
    $text = Replace-Exact $text 'import { index, integer, primaryKey, sqliteTable, text } from "drizzle-orm/sqlite-core";' 'import { index, primaryKey, sqliteTable, text } from "drizzle-orm/sqlite-core";' 'schema import'
    $text = Replace-Range -Text $text -StartMarker 'export const oauthClients = sqliteTable("oauth_clients", {' -EndMarker 'export const localAgentSessions = sqliteTable("local_agent_sessions", {' -Replacement '' -Label 'schema oauth tables'
    Set-Text $schemaPath $text

    $userConfigPath = Join-Path $PackageRoot 'dist/user-config.js'
    $text = Get-Text $userConfigPath
    $oldRandomBytesImport = 'import { randomBytes } from "node:crypto";' + "`n"
    $text = Replace-Exact -Text $text -Old $oldRandomBytesImport -New '' -Label 'user config randomBytes'
    $text = Replace-Range -Text $text -StartMarker 'export function devspaceAuthPath(env = process.env) {' -EndMarker 'export function devspaceSkillsDir(env = process.env) {' -Replacement '' -Label 'user config auth path'
    $loadFiles = @'
export function loadDevspaceFiles(env = process.env) {
    const dir = devspaceConfigDir(env);
    const configPath = join(dir, "config.json");
    const configExists = existsSync(configPath);
    return {
        dir,
        configPath,
        configExists,
        config: configExists ? readJsonFile(configPath) : {},
    };
}
'@
    $loadFiles += "`n"
    $text = Replace-Range $text 'export function loadDevspaceFiles(env = process.env) {' 'export function writeDevspaceConfig(config, env = process.env) {' $loadFiles 'user config load files'
    $text = Replace-Range -Text $text -StartMarker 'export function writeDevspaceAuth(auth, env = process.env) {' -EndMarker 'export function ensureDevspaceDefaultSkills(env = process.env) {' -Replacement '' -Label 'user config auth helpers'
    Set-Text $userConfigPath $text

    $serverPath = Join-Path $PackageRoot 'dist/server.js'
    $text = Get-Text $serverPath
    $oldAuthRouterImport = 'import { mcpAuthRouter, getOAuthProtectedResourceMetadataUrl } from "@modelcontextprotocol/sdk/server/auth/router.js";' + "`n"
    $text = Replace-Exact -Text $text -Old $oldAuthRouterImport -New '' -Label 'server auth router import'
    $text = Replace-Exact $text 'import { checkResourceAllowed, resourceUrlFromServerUrl } from "@modelcontextprotocol/sdk/shared/auth-utils.js";' 'import { checkResourceAllowed } from "@modelcontextprotocol/sdk/shared/auth-utils.js";' 'server auth utils import'
    $text = Replace-Exact $text 'import { SingleUserOAuthProvider } from "./oauth-provider.js";' 'import { RemoteJWTVerifier } from "./remote-auth.js";' 'server verifier import'
    $authSetup = @'
    const resourceServerUrl = new URL(config.oauth.resourceUrl);
    const oauthIssuer = new URL(config.oauth.issuer);
    const bearerAuth = requireBearerAuth({
        verifier: new RemoteJWTVerifier({
            jwksUri: config.oauth.jwksUri,
            issuer: config.oauth.issuer,
            audience: resourceServerUrl.href,
        }),
        requiredScopes: config.oauth.scopes,
        resourceMetadataUrl: new URL("/.well-known/oauth-protected-resource", resourceServerUrl).href,
    });
'@
    $authSetup += "`n"
    $text = Replace-Range $text '    const mcpUrl = new URL("/mcp", config.publicBaseUrl);' '    const workspaceStore = createWorkspaceStore(config.stateDir);' $authSetup 'server auth setup'
    $metadataRoute = @'
    app.get("/.well-known/oauth-protected-resource", (_req, res) => {
        res.json({
            resource: resourceServerUrl.href,
            authorization_servers: [oauthIssuer.href],
            scopes_supported: config.oauth.scopes,
            resource_name: "DevSpace",
        });
    });
'@
    $metadataRoute += "`n"
    $text = Replace-Range $text '    app.use(mcpAuthRouter({' '    app.options("/mcp-app-assets/{*asset}", (_req, res) => {' $metadataRoute 'server metadata route'
    $text = Replace-Exact -Text $text -Old "                oauthProvider.close();`n" -New '' -Label 'server oauth close'
    $text = Replace-Exact $text '        console.log("auth: oauth owner-token flow required");' '        console.log("auth: Authelia OAuth Resource Server");' 'server auth log'
    Set-Text $serverPath $text

    $remoteAuthBase64 = 'aW1wb3J0IHsgSW52YWxpZFRva2VuRXJyb3IgfSBmcm9tICJAbW9kZWxjb250ZXh0cHJvdG9jb2wvc2RrL3NlcnZlci9hdXRoL2Vycm9ycy5qcyI7CmltcG9ydCB7IGNyZWF0ZVJlbW90ZUpXS1NldCwgand0VmVyaWZ5IH0gZnJvbSAiam9zZSI7CgpmdW5jdGlvbiBub3JtYWxpemVJc3N1ZXIodmFsdWUpIHsKICAgIHJldHVybiB2YWx1ZS5yZXBsYWNlKC9cLyskLywgIiIpOwp9CgpmdW5jdGlvbiBwYXJzZVNjb3Blcyh2YWx1ZSkgewogICAgaWYgKHR5cGVvZiB2YWx1ZSA9PT0gInN0cmluZyIpIHsKICAgICAgICByZXR1cm4gdmFsdWUuc3BsaXQoL1xzKy8pLm1hcCgoc2NvcGUpID0+IHNjb3BlLnRyaW0oKSkuZmlsdGVyKEJvb2xlYW4pOwogICAgfQogICAgaWYgKEFycmF5LmlzQXJyYXkodmFsdWUpKSB7CiAgICAgICAgcmV0dXJuIHZhbHVlLm1hcCgoc2NvcGUpID0+IFN0cmluZyhzY29wZSkpLmZpbHRlcihCb29sZWFuKTsKICAgIH0KICAgIHJldHVybiBbXTsKfQoKLyoqIOS9v+eUqCBBdXRoZWxpYSBKV0tTIOagoemqjOiuv+mXruS7pOeJjO+8m0RldlNwYWNlIOS4jeWGjeetvuWPkeaIluS/neWtmCBPQXV0aCDku6TniYzjgIIgKi8KZXhwb3J0IGNsYXNzIFJlbW90ZUpXVFZlcmlmaWVyIHsKICAgIGlzc3VlcjsKICAgIGF1ZGllbmNlOwogICAgandrczsKCiAgICBjb25zdHJ1Y3Rvcih7IGp3a3NVcmksIGlzc3VlciwgYXVkaWVuY2UgfSkgewogICAgICAgIHRoaXMuaXNzdWVyID0gbm9ybWFsaXplSXNzdWVyKGlzc3Vlcik7CiAgICAgICAgdGhpcy5hdWRpZW5jZSA9IGF1ZGllbmNlOwogICAgICAgIHRoaXMuandrcyA9IGNyZWF0ZVJlbW90ZUpXS1NldChuZXcgVVJMKGp3a3NVcmkpKTsKICAgIH0KCiAgICBhc3luYyB2ZXJpZnlBY2Nlc3NUb2tlbih0b2tlbikgewogICAgICAgIGlmICh0eXBlb2YgdG9rZW4gIT09ICJzdHJpbmciIHx8IHRva2VuLnNwbGl0KCIuIikubGVuZ3RoICE9PSAzKSB7CiAgICAgICAgICAgIHRocm93IG5ldyBJbnZhbGlkVG9rZW5FcnJvcigiSW52YWxpZCBhY2Nlc3MgdG9rZW4iKTsKICAgICAgICB9CgogICAgICAgIHRyeSB7CiAgICAgICAgICAgIGNvbnN0IHsgcGF5bG9hZCB9ID0gYXdhaXQgand0VmVyaWZ5KHRva2VuLCB0aGlzLmp3a3MsIHsKICAgICAgICAgICAgICAgIGFsZ29yaXRobXM6IFsiUlMyNTYiXSwKICAgICAgICAgICAgICAgIGlzc3VlcjogdGhpcy5pc3N1ZXIsCiAgICAgICAgICAgICAgICBhdWRpZW5jZTogdGhpcy5hdWRpZW5jZSwKICAgICAgICAgICAgICAgIHJlcXVpcmVkQ2xhaW1zOiBbImV4cCIsICJpYXQiLCAiaXNzIiwgImF1ZCJdLAogICAgICAgICAgICB9KTsKCiAgICAgICAgICAgIHJldHVybiB7CiAgICAgICAgICAgICAgICB0b2tlbiwKICAgICAgICAgICAgICAgIGNsaWVudElkOiBTdHJpbmcocGF5bG9hZC5jbGllbnRfaWQgPz8gcGF5bG9hZC5henAgPz8gcGF5bG9hZC5zdWIgPz8gInVua25vd24iKSwKICAgICAgICAgICAgICAgIHNjb3BlczogcGFyc2VTY29wZXMocGF5bG9hZC5zY29wZSA/PyBwYXlsb2FkLnNjcCksCiAgICAgICAgICAgICAgICBleHBpcmVzQXQ6IE51bWJlcihwYXlsb2FkLmV4cCksCiAgICAgICAgICAgICAgICByZXNvdXJjZTogbmV3IFVSTCh0aGlzLmF1ZGllbmNlKSwKICAgICAgICAgICAgICAgIGV4dHJhOiB7IGNsYWltczogcGF5bG9hZCB9LAogICAgICAgICAgICB9OwogICAgICAgIH0KICAgICAgICBjYXRjaCB7CiAgICAgICAgICAgIHRocm93IG5ldyBJbnZhbGlkVG9rZW5FcnJvcigiSW52YWxpZCBhY2Nlc3MgdG9rZW4iKTsKICAgICAgICB9CiAgICB9Cn0K'
    [System.IO.File]::WriteAllBytes(
        (Join-Path $PackageRoot 'dist/remote-auth.js'),
        [Convert]::FromBase64String($remoteAuthBase64)
    )

    Remove-Item -LiteralPath (Join-Path $PackageRoot 'dist/oauth-provider.js')
    Remove-Item -LiteralPath (Join-Path $PackageRoot 'dist/oauth-store.js')

    $problems = @()
    foreach ($entry in $PatchedHashes.GetEnumerator()) {
        $path = Join-Path $PackageRoot $entry.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $problems += "$($entry.Key)=missing"
            continue
        }
        $actual = Get-Hash $path
        if ($actual -ne $entry.Value) {
            $problems += "$($entry.Key)=$actual expected=$($entry.Value)"
        }
    }
    foreach ($obsolete in @('dist/oauth-provider.js', 'dist/oauth-store.js')) {
        if (Test-Path -LiteralPath (Join-Path $PackageRoot $obsolete)) {
            $problems += "$obsolete=still-present"
        }
    }
    if ($problems.Count -gt 0) {
        throw "Post-write hash verification failed: $($problems -join '; ')"
    }
}
catch {
    foreach ($entry in $OfficialHashes.GetEnumerator()) {
        $backup = Join-Path $backupRoot $entry.Key
        $target = Join-Path $PackageRoot $entry.Key
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($target)) -Force | Out-Null
        Copy-Item -LiteralPath $backup -Destination $target -Force
    }
    Remove-Item -LiteralPath (Join-Path $PackageRoot 'dist/remote-auth.js') -Force -ErrorAction SilentlyContinue
    throw "Patch failed and official files were restored. Reason: $($_.Exception.Message)"
}

Write-Output "DevSpace Authelia auth patch applied: $PackageRoot"
Write-Output "Backup: $backupRoot"
