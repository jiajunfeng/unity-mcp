# IfGame Unity MCP Server Detailed Deployment Plan

## 1. Goal

This document turns the current ad-hoc deployment on `ifgame@192.168.1.204` into a controlled deployment process with:

- a clear current-state inventory
- a migration path from today's scripts to a managed service
- a repeatable release procedure
- an explicit rollback procedure
- a future automation path

This plan is based on the actual deployment scripts and runtime layout currently present on `192.168.1.204`, inspected on `2026-04-15`.

## 1A. Status Update On `2026-04-17`

Since the first draft of this document, the runtime portability cleanup has already been partially implemented on `192.168.1.204`.

Completed work:

- introduced a shared runtime root at:

```text
/data/ifgame/server/shared-runtime
```

- copied the working Python runtime to:

```text
/data/ifgame/server/shared-runtime/python/python310_ssl11
```

- copied the working OpenSSL 1.1.1 runtime to:

```text
/data/ifgame/server/shared-runtime/openssl-1.1.1w
```

- updated `UnityMCP` runtime configuration to use the shared runtime instead of:
  - `/usr/local/python310_ssl11`
  - project-local `toolchain/openssl111`
- rebuilt `Server/.venv` using the real `uv` binary on the host:

```text
/usr/local/ifgame/.local/bin/uv
```

- verified that:
  - `.venv/bin/python` resolves to the shared Python runtime
  - `_ssl.so` resolves to the shared OpenSSL runtime
  - `auth` on `10302` is healthy
  - `unity-mcp` on `10301` is healthy
- updated `start-mcp.sh` to use a startup wait loop instead of a fixed `sleep 2`, to avoid false startup failures after a fresh `.venv` rebuild
- pulled the active `deploy/` scripts back into the local repo and put them under version control
- added a local deploy helper:

```text
tools/deploy_ifgame_server.sh
```

- validated one full end-to-end release from the local repo to `192.168.1.204` using that helper script

Current effective runtime state:

- active Python runtime:

```text
/data/ifgame/server/shared-runtime/python/python310_ssl11/bin/python3.10
```

- active OpenSSL runtime:

```text
/data/ifgame/server/shared-runtime/openssl-1.1.1w
```

- active `uv` binary:

```text
/usr/local/ifgame/.local/bin/uv
```

Current note:

- `/usr/local/python310_ssl11` may still exist on disk, but it is no longer part of the active service runtime chain
- the service runtime now depends on `shared-runtime`, not on the old `/usr/local/python310_ssl11` path
- the currently validated release path is:
  - local repo -> `rsync` to `204`
  - remote `uv sync`
  - remote `deploy/restart-all.sh`
  - remote `deploy/status-all.sh`

## 2. Observed Current State On `192.168.1.204`

### 2.1 Actual deployment root

The path currently used by operations is:

```text
/usr/local/ifgame/iaf/server/UnityMCP
```

This is a symlink to:

```text
/data/ifgame/server/UnityMCP
```

### 2.2 Actual runtime model

The service is currently managed by shell scripts under:

```text
/data/ifgame/server/UnityMCP/deploy
```

Observed files:

- `start-mcp.sh`
- `stop-mcp.sh`
- `start-auth.sh`
- `stop-auth.sh`
- `start-all.sh`
- `stop-all.sh`
- `restart-all.sh`
- `restart-auth.sh`
- `status-all.sh`
- `server.env`
- `auth.env`
- `auth_service.py`
- `auth_keys.txt`

### 2.3 Actual process model

Current long-running processes:

- `mcp-for-unity` process managed by `nohup`
- `auth_service.py` process managed by `nohup`

Observed ports:

- Unity MCP HTTP server: `10301`
- local auth service: `10302`

Observed PID files:

- `/usr/local/ifgame/iaf/server/UnityMCP/run/unity-mcp.pid`
- `/usr/local/ifgame/iaf/server/UnityMCP/run/auth.pid`

Observed logs:

- `/usr/local/ifgame/iaf/server/UnityMCP/logs/mcp.out`
- `/usr/local/ifgame/iaf/server/UnityMCP/logs/auth.out`

### 2.4 Actual startup behavior

Current MCP startup command in `deploy/start-mcp.sh` is effectively:

```bash
$BASE/Server/.venv/bin/mcp-for-unity \
  --transport http \
  --http-host 0.0.0.0 \
  --http-port 10301 \
  --http-remote-hosted \
  --api-key-validation-url http://127.0.0.1:10302/api/validate-key \
  --api-key-login-url http://127.0.0.1:10302/api-keys \
  --project-scoped-tools \
  --pidfile /usr/local/ifgame/iaf/server/UnityMCP/run/unity-mcp.pid
```

Current auth service behavior:

- a simple Python HTTP server
- key store backed by `deploy/auth_keys.txt`
- validation endpoint: `POST /api/validate-key`
- login URL endpoint: `GET /api-keys`
- health endpoint: `GET /health`

### 2.5 Actual environment assumptions

Current deployment depends on:

- custom Python path via `PY310_HOME=/usr/local/python310_ssl11`
- custom OpenSSL path via `OPENSSL_HOME=/usr/local/ifgame/iaf/server/UnityMCP/toolchain/openssl111`
- manual `LD_LIBRARY_PATH` injection
- `HOME=/usr/local/ifgame/iaf/server/UnityMCP/runtime`

### 2.6 Actual repository state on the server

The production directory is also a git checkout.

Observed facts:

- branch: `beta`
- current commit: `ec25df8`
- working tree is dirty
- deployment-only directories such as `deploy/`, `logs/`, `run/`, `runtime/`, and `toolchain/` live inside the same repo root

This means production code, deployment assets, runtime artifacts, and local modifications are currently mixed together.

### 2.7 Current script mapping

Current scripts and their responsibilities:

- `start-auth.sh`: starts local auth service in background
- `stop-auth.sh`: stops local auth service by PID
- `start-mcp.sh`: starts Python MCP server in background
- `stop-mcp.sh`: stops Python MCP server by PID
- `start-all.sh`: starts auth then MCP
- `stop-all.sh`: stops MCP then auth
- `restart-all.sh`: stop-all then start-all
- `status-all.sh`: checks PID files and curls both `/health` endpoints

This means there is already a useful operational contract, but it is not managed by the OS and is not release-oriented.

### 2.8 Python runtime portability findings

The current Python runtime is not generic.

Observed facts from `192.168.1.204`:

- the virtualenv interpreter at `/data/ifgame/server/UnityMCP/Server/.venv/bin/python` is a symlink to:

```text
/usr/local/python310_ssl11/bin/python3.10
```

- the Python binary itself is present on the host and is not part of the app release payload
- the `_ssl` extension depends on:
  - `libssl.so.1.1`
  - `libcrypto.so.1.1`
- those libraries are not resolved by default from the system library path
- they are supplied by the deployment-private OpenSSL bundle under:

```text
/data/ifgame/server/UnityMCP/toolchain/openssl111/lib
```

- current startup succeeds only because `start-mcp.sh` injects:
  - `OPENSSL_HOME`
  - `LD_LIBRARY_PATH`
  - `PY310_HOME`

Observed runtime proof:

- Python executable: `/usr/local/python310_ssl11/bin/python3.10`
- SSL runtime reported by Python: `OpenSSL 1.1.1w 11 Sep 2023`

Conclusion:

- the current deployment is tightly coupled to one host-local Python installation and one host-local OpenSSL layout
- copying the repo or copying only `.venv` to another machine will not be sufficient
- the first migration must address application deployment and Python runtime portability as two separate concerns

### 2.9 Runtime portability status after the 2026-04-17 implementation

The original runtime portability problem has been reduced, but not fully eliminated.

Resolved on `192.168.1.204`:

- active `.venv` no longer points at `/usr/local/python310_ssl11`
- active OpenSSL no longer depends on project-local `toolchain/openssl111`
- the service now runs against the shared runtime under `/data/ifgame/server/shared-runtime`
- the virtual environment has been rebuilt using `uv`, rather than only re-pointing the interpreter symlink

Still not fully generalized:

- the shared runtime is host-local to `192.168.1.204`
- the runtime is still not packaged as a formal release artifact
- deployment is still script-managed rather than `systemd`-managed

## 3. Main Problems With The Current Model

### 3.1 In-place deployment risk

The live directory is the repo itself. Updating files in place creates these problems:

- no clean release boundary
- no atomic cutover
- hard to tell what is code vs local runtime state
- difficult rollback

### 3.2 Process supervision is weak

Current process model is `nohup + pidfile`.

Problems:

- no `systemd` restart policy
- no boot-time auto-recovery guarantee
- stale PID files must be handled by scripts
- logs grow forever unless handled separately

### 3.3 Deployment and runtime concerns are mixed

The same root contains:

- git checkout
- runtime logs
- runtime PID files
- local auth files
- custom toolchain
- deployment scripts

This makes updates fragile and increases accidental overwrite risk.

### 3.4 Auth service is operationally useful but under-managed

The auth service is simple and acceptable as a temporary local dependency, but:

- it has no separate service supervision
- keys are file-backed in `auth_keys.txt`
- it is not versioned as a standalone runtime component
- its lifecycle is tied to shell scripts instead of service management

### 3.5 Server commit is old and the tree is dirty

Because the running directory is on old commit `ec25df8` and has many local modifications, a naive `git pull` or direct overwrite is risky.

### 3.6 Python runtime is host-bound

The current Python runtime has these non-portable characteristics:

- interpreter path is absolute and external to the app release
- venv depends on a host-specific interpreter location
- SSL support depends on a private OpenSSL 1.1.1 bundle plus `LD_LIBRARY_PATH`
- service startup currently relies on shell-script environment injection to make `ssl` import work

This means the server is not yet deployable as a generic release artifact.

## 4. Target State

The target state should preserve the current logical behavior while changing the deployment mechanics.

Target principles:

- keep the same host: `192.168.1.204`
- keep the same base service path family: `/usr/local/ifgame/iaf/server/UnityMCP`
- keep the same exposed ports unless there is a reason to change them
- keep remote-hosted mode enabled
- keep local auth service behavior for now
- stop running directly from a mutable repo root

Target deployment model:

```text
/data/ifgame/server/UnityMCP/
  current -> /data/ifgame/server/UnityMCP/releases/<release_id>
  releases/
    <release_id>/
      Server/
      deploy/
      .release-meta
  shared/
    config/
      server.env
      auth.env
    logs/
      mcp/
      auth/
    run/
    auth/
      auth_keys.txt
    toolchain/
      openssl111/
    runtime/
    backups/
```

Key design choices:

- release directories are immutable after deployment
- `current` is the only active code pointer
- logs, pids, auth keys, runtime home, and toolchain move under `shared/`
- services are managed by `systemd`

Additional runtime portability principle:

- Python runtime must become a managed deployment asset, not an undeclared host prerequisite

## 5. Compatibility Rules For Migration

To reduce risk, this migration should preserve these behaviors in the first iteration:

- MCP server still listens on `0.0.0.0:10301`
- auth service still listens on `127.0.0.1:10302`
- MCP server still runs with `--http-remote-hosted`
- MCP server still uses local validation URL `http://127.0.0.1:10302/api/validate-key`
- MCP server still uses `--project-scoped-tools`
- telemetry remains disabled
- current auth key format `user:key` remains unchanged

This keeps client compatibility stable while the deployment mechanism is upgraded.

Additional compatibility rule for the first migration:

- keep Python `3.10 + OpenSSL 1.1.1` behavior in the first cutover, even if the packaging method changes

## 6. Recommended Service Split

Create two `systemd` units:

- `unity-mcp.service`
- `unity-mcp-auth.service`

Reason:

- current behavior already treats them as two separate processes
- separate units make restarts, logs, and failure domains clearer
- future replacement of the auth service becomes easier

## 6A. Python Runtime Portability Strategy

This is the most important runtime issue beyond the deployment scripts.

### Problem statement

Today the service depends on:

- `/usr/local/python310_ssl11/bin/python3.10`
- `/data/ifgame/server/UnityMCP/toolchain/openssl111/lib`
- shell-exported `LD_LIBRARY_PATH`

That makes the deployment:

- host-specific
- hard to reproduce on another machine
- fragile during migration

### Portability target

The goal is to make the Python runtime part of the managed deployment contract.

At minimum, a fresh target machine should be able to run the service if it receives:

- the application release payload
- the managed Python runtime payload
- the managed OpenSSL runtime payload
- the environment file
- the systemd unit files

without relying on undocumented host-local interpreter paths.

### Options

#### Option A: Keep current Python version, but vendor the runtime

Approach:

- keep Python `3.10`
- keep OpenSSL `1.1.1`
- move both into managed directories under `shared/`
- rebuild the venv against the managed interpreter

Pros:

- smallest behavior change
- safest short-term migration
- keeps compatibility with the currently working runtime

Cons:

- still tied to an old OpenSSL line
- still requires careful runtime packaging

#### Option B: Upgrade to a more standard host Python

Approach:

- use a standard system or packaged Python `3.11+`
- use a standard OpenSSL `3.x` environment
- rebuild the venv and retest the service

Pros:

- cleaner long-term state
- less custom runtime handling

Cons:

- higher migration risk
- requires compatibility verification for dependencies and current workload
- should not be bundled into the first deployment cleanup

#### Option C: Containerize the service

Approach:

- run the server and auth service in containers
- package Python and OpenSSL inside the image

Pros:

- best portability across hosts
- strongest runtime reproducibility

Cons:

- operationally larger change
- depends on container support and deployment preference

### Recommendation

Recommended path:

1. First migration: choose Option A
2. Later modernization: evaluate Option B or Option C

Reason:

- the immediate goal is to remove host-specific hidden dependencies without changing too many variables at once
- keeping the currently working Python/OpenSSL behavior while changing only the packaging method is the safest path

### Recommended managed runtime layout

```text
/data/ifgame/server/UnityMCP/shared/
  python/
    python310_ssl11/
      bin/python3.10
      lib/
  toolchain/
    openssl111/
      lib/libssl.so.1.1
      lib/libcrypto.so.1.1
  bin/
    unity-mcp-python
```

### Recommended first-cut implementation

#### Step 1: Treat Python runtime as a managed artifact

Copy the currently working runtime into managed locations:

- `/usr/local/python310_ssl11` -> `shared/python/python310_ssl11`
- `/data/ifgame/server/UnityMCP/toolchain/openssl111` -> `shared/toolchain/openssl111`

Do this before changing the service model.

#### Step 2: Add a managed Python wrapper

Create:

```text
/data/ifgame/server/UnityMCP/shared/bin/unity-mcp-python
```

Behavior:

- exports `OPENSSL_HOME`
- exports `LD_LIBRARY_PATH=$OPENSSL_HOME/lib:${LD_LIBRARY_PATH:-}`
- execs `shared/python/python310_ssl11/bin/python3.10`

Purpose:

- standardize runtime boot
- remove dependence on ad-hoc shell logic inside multiple scripts

#### Step 3: Rebuild the venv against the managed interpreter

Do not keep using a venv whose interpreter symlink points at `/usr/local/python310_ssl11`.

Instead:

- create the venv from `shared/python/python310_ssl11/bin/python3.10`
- or from the managed wrapper if that proves more reliable

Expected result:

- the venv is tied to the managed deployment runtime, not the old host-global path

#### Step 4: Add runtime preflight validation

Before each service start or each release activation, verify:

```bash
python -c "import ssl,sys; print(sys.executable); print(ssl.OPENSSL_VERSION)"
```

Also verify:

```bash
ldd <path-to-_ssl.so>
```

Expected result:

- `libssl.so.1.1` and `libcrypto.so.1.1` resolve from the managed runtime path

#### Step 5: Move systemd and wrappers to the managed runtime

After validation:

- `unity-mcp.service` should reference the managed venv
- environment files should point to `shared/python/...` and `shared/toolchain/...`
- no runtime path should depend on `/usr/local/python310_ssl11`

### What should not be considered “generic”

These are only partial fixes and should not be treated as a real portability solution:

- documenting “remember to install `/usr/local/python310_ssl11` manually”
- copying only `.venv` without the interpreter runtime
- relying on `LD_LIBRARY_PATH` from a login shell
- assuming another machine also has compatible `libssl.so.1.1`

### Long-term preferred end state

Best long-term outcomes, in order:

1. containerized runtime
2. standardized OS/runtime with system Python and standard OpenSSL
3. managed vendored runtime under `shared/`

For the next migration, target outcome should be number 3.

## 7. Migration Plan

### Phase 0: Freeze And Inventory

Objective:

- capture exact production state before any structural change

Tasks:

1. Record current running PIDs.
2. Record current branch, commit, and `git status`.
3. Back up `deploy/`, `logs/`, `run/`, `runtime/`, `toolchain/`, and `Server/.venv`.
4. Back up `deploy/auth_keys.txt`.
5. Save the current `start/stop/status` scripts as migration references.

Commands to record:

```bash
cd /data/ifgame/server/UnityMCP
git status --short --branch
git rev-parse HEAD
ps -ef | grep -E 'mcp-for-unity|auth_service.py' | grep -v grep
```

Mandatory backup:

```bash
mkdir -p /data/ifgame/server/UnityMCP-migration-snapshot-$(date +%Y%m%d-%H%M%S)
cp -a /data/ifgame/server/UnityMCP/deploy /data/ifgame/server/UnityMCP-migration-snapshot-$(date +%Y%m%d-%H%M%S)/
cp -a /data/ifgame/server/UnityMCP/logs /data/ifgame/server/UnityMCP-migration-snapshot-$(date +%Y%m%d-%H%M%S)/
cp -a /data/ifgame/server/UnityMCP/run /data/ifgame/server/UnityMCP-migration-snapshot-$(date +%Y%m%d-%H%M%S)/
cp -a /data/ifgame/server/UnityMCP/runtime /data/ifgame/server/UnityMCP-migration-snapshot-$(date +%Y%m%d-%H%M%S)/
cp -a /data/ifgame/server/UnityMCP/toolchain /data/ifgame/server/UnityMCP-migration-snapshot-$(date +%Y%m%d-%H%M%S)/
```

Exit criteria:

- all runtime artifacts and deploy scripts are backed up
- current state is documented

### Phase 1: Build The Managed Directory Layout

Objective:

- introduce release and shared directories without changing the live service yet

Create:

```bash
mkdir -p /data/ifgame/server/UnityMCP/releases
mkdir -p /data/ifgame/server/UnityMCP/shared/config
mkdir -p /data/ifgame/server/UnityMCP/shared/logs/mcp
mkdir -p /data/ifgame/server/UnityMCP/shared/logs/auth
mkdir -p /data/ifgame/server/UnityMCP/shared/run
mkdir -p /data/ifgame/server/UnityMCP/shared/auth
mkdir -p /data/ifgame/server/UnityMCP/shared/python
mkdir -p /data/ifgame/server/UnityMCP/shared/bin
mkdir -p /data/ifgame/server/UnityMCP/shared/runtime
mkdir -p /data/ifgame/server/UnityMCP/shared/backups
mkdir -p /data/ifgame/server/UnityMCP/shared/toolchain
```

Then migrate persistent assets:

- copy `deploy/auth_keys.txt` to `shared/auth/auth_keys.txt`
- copy OpenSSL toolchain to `shared/toolchain/openssl111` if still required
- copy the currently working Python runtime to `shared/python/python310_ssl11`
- plan to point `HOME` to `shared/runtime`

Exit criteria:

- shared directories exist
- no live traffic has been moved yet

### Phase 2: Externalize Runtime Configuration

Objective:

- turn current inline assumptions into stable config files

New config files:

- `shared/config/server.env`
- `shared/config/auth.env`

Expected `server.env` fields:

```bash
HOME=/data/ifgame/server/UnityMCP/shared/runtime

OPENSSL_HOME=/data/ifgame/server/UnityMCP/shared/toolchain/openssl111
PY310_HOME=/data/ifgame/server/UnityMCP/shared/python/python310_ssl11

LD_LIBRARY_PATH=$OPENSSL_HOME/lib:${LD_LIBRARY_PATH:-}
PATH=$PY310_HOME/bin:${PATH:-}

UNITY_MCP_TRANSPORT=http
UNITY_MCP_HTTP_HOST=0.0.0.0
UNITY_MCP_HTTP_PORT=10301

UNITY_MCP_HTTP_REMOTE_HOSTED=true
UNITY_MCP_API_KEY_VALIDATION_URL=http://127.0.0.1:10302/api/validate-key
UNITY_MCP_API_KEY_LOGIN_URL=http://127.0.0.1:10302/api-keys
UNITY_MCP_API_KEY_CACHE_TTL=300

UNITY_MCP_PROJECT_SCOPED_TOOLS=true
UNITY_MCP_SKIP_STARTUP_CONNECT=1
DISABLE_TELEMETRY=1
```

Expected `auth.env` fields:

```bash
AUTH_HOST=127.0.0.1
AUTH_PORT=10302
AUTH_KEYS_FILE=/data/ifgame/server/UnityMCP/shared/auth/auth_keys.txt
```

Exit criteria:

- all runtime values come from config files, not only hardcoded scripts

### Phase 3: Create The First Managed Release

Objective:

- create a clean deployable release from the local repo

Recommended release content:

- `Server/`
- `deploy/auth_service.py` or another managed auth-service entrypoint
- optional deployment helper scripts
- release metadata file with commit SHA and timestamp

Important current-state note:

- `auth_service.py` exists on `192.168.1.204` today, but it is currently a server-local operational script, not part of the synced local repo.
- Before the first managed release, this file must either be:
  - imported into version control in a dedicated ops path, or
  - copied from the current production snapshot into the managed release payload.

Recommended release ID:

```text
YYYYMMDD-HHMMSS-<short_sha>
```

Local source of truth:

- use the local repo after the upstream sync
- deploy a pinned commit only

Server-side layout example:

```text
/data/ifgame/server/UnityMCP/releases/20260415-220000-8123820/
  Server/
  deploy/
  .release-meta
```

Exit criteria:

- a new release directory exists
- `uv sync --frozen --no-dev` succeeds inside the release `Server/`

Operational note from the `2026-04-17` implementation:

- on `192.168.1.204`, the actual usable `uv` path is `/usr/local/ifgame/.local/bin/uv`
- future deploy scripts should use the absolute `uv` path or explicitly inject its directory into `PATH`

### Phase 4: Replace `nohup` With `systemd`

Objective:

- keep current behavior while switching supervision model

Create unit:

`/etc/systemd/system/unity-mcp-auth.service`

Suggested behavior:

- `WorkingDirectory=/data/ifgame/server/UnityMCP/current`
- `EnvironmentFile=/data/ifgame/server/UnityMCP/shared/config/auth.env`
- `ExecStart=/data/ifgame/server/UnityMCP/current/Server/.venv/bin/python /data/ifgame/server/UnityMCP/current/deploy/auth_service.py`
- restart automatically on failure
- write logs to dedicated files or use `journalctl`

Create unit:

`/etc/systemd/system/unity-mcp.service`

Suggested behavior:

- `WorkingDirectory=/data/ifgame/server/UnityMCP/current/Server`
- `EnvironmentFile=/data/ifgame/server/UnityMCP/shared/config/server.env`
- `ExecStart=/data/ifgame/server/UnityMCP/current/Server/.venv/bin/mcp-for-unity --transport http --http-host 0.0.0.0 --http-port 10301 --http-remote-hosted --api-key-validation-url http://127.0.0.1:10302/api/validate-key --api-key-login-url http://127.0.0.1:10302/api-keys --project-scoped-tools --pidfile /data/ifgame/server/UnityMCP/shared/run/unity-mcp.pid`
- `Requires=unity-mcp-auth.service`
- `After=unity-mcp-auth.service`
- restart automatically on failure

Important note:

- keeping `--pidfile` in the first iteration reduces behavioral change and preserves compatibility with current status checks
- the unit should use the managed runtime path, not `/usr/local/python310_ssl11`

Exit criteria:

- both services can be started and stopped by `systemctl`
- manual `nohup` is no longer required

### Phase 5: Build Compatibility Wrappers

Objective:

- avoid breaking existing operator habits during migration

Keep the current operator entrypoints, but turn them into wrappers:

- `deploy/start-all.sh` -> `systemctl start unity-mcp-auth unity-mcp`
- `deploy/stop-all.sh` -> `systemctl stop unity-mcp unity-mcp-auth`
- `deploy/restart-all.sh` -> `systemctl restart unity-mcp-auth unity-mcp`
- `deploy/status-all.sh` -> `systemctl status` plus curl health checks

This reduces retraining cost and allows gradual adoption.

Exit criteria:

- existing operational commands still work
- their implementation now delegates to `systemd`

### Phase 6: Cutover

Objective:

- switch from old mutable repo-root runtime to managed release runtime

Cutover order:

1. Stop current `nohup`-managed services using existing scripts.
2. Update `current` symlink to the first managed release.
3. Start `unity-mcp-auth.service`.
4. Verify auth service health on `127.0.0.1:10302/health`.
5. Start `unity-mcp.service`.
6. Verify MCP health on `127.0.0.1:10301/health`.
7. Verify plugin and MCP clients can authenticate and connect.

Validation checklist:

```bash
curl -f http://127.0.0.1:10302/health
curl -f http://127.0.0.1:10301/health
systemctl status unity-mcp-auth --no-pager
systemctl status unity-mcp --no-pager
```

Functional checks:

- remote-hosted API key validation still works
- `/api-keys` still returns expected response
- Unity plugin can connect to `/hub/plugin`
- MCP clients can call `/mcp` with valid `X-API-Key`

Exit criteria:

- production traffic is served by `systemd`-managed processes from `current`

### Phase 7: Clean Separation Of Repo And Runtime

Objective:

- eliminate the need to use the production root as a mutable git checkout

After at least one successful managed release:

- keep old repo-root deployment only as emergency fallback for a short window
- stop doing `git` operations in the production runtime path
- treat new deployments as payload syncs into `releases/<release_id>`

Preferred long-term rule:

- production runtime path is not a developer working tree

Exit criteria:

- new releases are deployed without mutating the previous release directory

## 8. Current Recommended Release Procedure

This is the release flow that is currently implemented and validated.

It does not depend on `systemd`, release symlinks, or a second deployment root yet.

Instead, it uses:

- version-controlled `deploy/` scripts in this repo
- shared runtime on `192.168.1.204`
- direct sync into `/data/ifgame/server/UnityMCP`
- remote `uv sync`
- remote `deploy/restart-all.sh`

### 8.1 Preconditions

Before using the release script, the following must already exist on `192.168.1.204`:

- shared Python runtime:

```text
/data/ifgame/server/shared-runtime/python/python310_ssl11
```

- shared OpenSSL runtime:

```text
/data/ifgame/server/shared-runtime/openssl-1.1.1w
```

- remote `uv`:

```text
/usr/local/ifgame/.local/bin/uv
```

- target service root:

```text
/data/ifgame/server/UnityMCP
```

### 8.2 Local precheck

```bash
cd /Users/jiajunfeng/Git/unity-mcp
git status --short --branch
git rev-parse --short HEAD
```

Recommended verification:

```bash
cd /Users/jiajunfeng/Git/unity-mcp/Server
uv sync --frozen --no-dev
uv run pytest
```

Minimum fallback gate:

- `uv run pytest tests/test_cli.py`
- `uv run pytest tests/test_transport_characterization.py`
- `uv run pytest tests/test_manage_editor.py`

### 8.3 Deploy script entrypoint

The current deploy helper is:

```text
tools/deploy_ifgame_server.sh
```

Default behavior:

- sync local `Server/` to `ifgame@192.168.1.204:/data/ifgame/server/UnityMCP/Server/`
- sync local `deploy/` to `ifgame@192.168.1.204:/data/ifgame/server/UnityMCP/deploy/`
- exclude:
  - `.venv`
  - local caches
  - `deploy/auth_keys.txt`
  - `deploy/auth_keys.example.txt`
  - `deploy/*.bak_*`
- run remote:
  - `/usr/local/ifgame/.local/bin/uv sync --frozen --no-dev --python /data/ifgame/server/shared-runtime/python/python310_ssl11/bin/python3.10`
- run remote:
  - `deploy/restart-all.sh`
  - `deploy/status-all.sh`

### 8.4 Standard release command

From the local repo root:

```bash
bash tools/deploy_ifgame_server.sh
```

Optional overrides:

```bash
REMOTE_HOST=ifgame@192.168.1.204 \
REMOTE_BASE=/data/ifgame/server/UnityMCP \
REMOTE_UV=/usr/local/ifgame/.local/bin/uv \
REMOTE_PYTHON=/data/ifgame/server/shared-runtime/python/python310_ssl11/bin/python3.10 \
bash tools/deploy_ifgame_server.sh
```

### 8.5 What the deploy script actually does

Step 1:

- `rsync` local `Server/` to the remote service directory

Step 2:

- `rsync` local `deploy/` to the remote service directory

Step 3:

- execute remote `uv sync --frozen --no-dev --python <shared-runtime-python>`

Step 4:

- restart remote `auth` and `unity-mcp`

Step 5:

- print remote status and health checks

### 8.6 Validation result already observed

This workflow has already been run successfully end-to-end.

Observed result from the validated release:

- remote sync completed
- remote `uv sync` completed
- remote services restarted successfully
- `auth` health check passed
- `unity-mcp` health check passed
- server package version on `204` was updated to `9.6.6`

### 8.7 Operational notes

Important notes:

- `deploy/auth_keys.txt` is intentionally not synced from the local repo
- the real auth key file remains server-local operational data
- local version control should keep only `deploy/auth_keys.example.txt`
- the release script assumes passwordless SSH or an already usable SSH session to `ifgame@192.168.1.204`
- if remote `uv` is not on `PATH`, keep using its absolute path in the deploy script

### 8.8 Future evolution

This script-based deployment flow is the current recommended operational path.

The earlier `systemd + releases/current symlink` design remains a longer-term target, but it is not required for the current operating model.

## 9. Rollback Plan

Rollback for the current script-based model is restore-by-sync, not symlink-based.

Rollback steps:

1. identify the previous known-good local commit
2. sync that code and `deploy/` state back to `204`
3. run remote `uv sync`
4. restart services
5. rerun health checks

Commands:

```bash
git checkout <known-good-commit>
bash tools/deploy_ifgame_server.sh
```

Rollback success criteria:

- both health endpoints respond
- service startup matches previous known-good behavior

## 10. Risks And Mitigations

### Risk 1: Custom Python/OpenSSL dependency breaks after layout change

Mitigation:

- preserve Python `3.10 + OpenSSL 1.1.1` behavior first
- vendor both runtime components into managed paths
- do not change Python runtime in the same migration
- test `uv sync` and service startup before cutover
- do not assume `uv` is on `PATH` in non-login shells; use an absolute path if needed

### Risk 2: Auth service path changes break API key validation

Mitigation:

- move only the file path, not the endpoint contract
- keep `127.0.0.1:10302`
- keep `user:key` file format

### Risk 3: Existing clients rely on current ports and paths

Mitigation:

- do not change `10301` or `10302` in the first migration
- keep compatibility wrappers in `deploy/`

### Risk 4: Dirty old repo contains manual fixes not yet in local repo

Mitigation:

- do not overwrite production blindly
- inventory and diff current server tree before the first managed release
- explicitly reconcile local code with any production-only changes

### Risk 5: Log files continue growing without rotation

Mitigation:

- if file logging is kept, add `logrotate`
- if journald is used, define retention policy

## 11. Decisions Recommended Before Execution

These choices should be confirmed before actual migration:

1. Keep local file-backed auth service temporarily, or replace it now.
2. Keep current ports `10301/10302`, or standardize later.
3. Keep `pidfile` during the first managed-service iteration, or drop it immediately.
4. Keep file logs under `shared/logs`, or move fully to `journalctl`.
5. Keep host-local `/usr/local/python310_ssl11`, or vendor the runtime into `shared/python`.

Recommended answers for the first migration:

- keep local auth service
- keep current ports
- keep `pidfile`
- keep file logs first, optimize later
- vendor the current Python runtime into `shared/python`

This minimizes moving parts during the cutover.

## 12. Immediate Next Work Items

The next concrete deliverables should be:

1. keep local `deploy/` and remote `deploy/` synchronized through normal code review and release flow
2. document the operational use of `tools/deploy_ifgame_server.sh`
3. decide whether to keep the current script-based model long-term or continue toward `systemd`
4. add optional log rotation for `logs/auth.out` and `logs/mcp.out`
5. decide whether `auth_keys.txt` should remain file-backed or move to a more formal secret source

Items already completed on `192.168.1.204`:

- shared Python runtime created under `shared-runtime`
- shared OpenSSL runtime created under `shared-runtime`
- active `.venv` rebuilt with `uv`
- active runtime switched away from `/usr/local/python310_ssl11`
- `start-mcp.sh` startup wait behavior improved
- active `deploy/` scripts pulled back into the local repo
- end-to-end deploy helper script created and validated

## 13. Acceptance Criteria

For the current script-based operating model, this plan is complete only when all of the following are true in production:

- local `deploy/` scripts are version-controlled and match the remote active scripts
- release to `204` can be done from the local repo with one documented command
- remote `.venv` is rebuilt via `uv` against the shared runtime
- runtime state is no longer dependent on `/usr/local/python310_ssl11`
- operators can use simple `start/stop/restart/status` entrypoints
- the service still authenticates via the local auth endpoint on `10302`
- both health endpoints respond after release

Longer-term desired end state:

- the running MCP server is started by `systemd`
- the running auth service is started by `systemd`
- production code is served from `current -> releases/<release_id>`
- rollback is symlink-based instead of sync-based
