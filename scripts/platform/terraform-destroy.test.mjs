import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, writeFileSync, readFileSync, mkdirSync, rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';

const bash = process.platform === 'win32' ? join(process.env.ProgramFiles, 'Git/bin/bash.exe') : 'bash';
const shellPath = path => process.platform === 'win32' ? path.replaceAll('\\', '/').replace(/^([A-Za-z]):/, (_, drive) => '/' + drive.toLowerCase()) : path;

function destroy({failCleanup = false, invalidVolume = false, stage = 'messaging', operation = 'destroy'} = {}) {
  const prefix = join(tmpdir(), 'fiap-destroy-test-');
  const directory = mkdtempSync(prefix);
  assert.ok(directory.startsWith(prefix));
  const bin = join(directory, 'bin');
  mkdirSync(bin);
  const log = join(directory, 'calls');
  const stub = (name, content = '') => writeFileSync(join(bin, name),
    `#!/bin/bash\nprintf '%s\\n' '${name} '"$*" >> "$CALL_LOG"\n${content}\n`, {mode:0o755});
  stub('git', "printf '%040d' 0");
  stub('terraform', 'if [[ "$*" == *"state list"* ]]; then echo kubernetes_manifest.mongodb; fi');
  // Impede que o ensaio instale kubectl ou consulte qualquer conta AWS.
  stub('bash');
  stub('node');
  stub('aws');
  stub('kubectl', `case "$*" in
    '-n fiap-messaging get pvc '*) echo pv-kafka ;;
    '-n fiap-mongodb get pvc '*) echo pv-mongodb ;;
    'get pv pv-kafka '*) echo ${invalidVolume ? 'unexpected-disk' : 'vol-abcd'} ;;
    'get pv pv-mongodb '*) echo vol-cdef ;;
    'get namespace fiap-messaging '*) ;; # Terraform ja removeu esse namespace.
    'get namespace fiap-mongodb '*) echo namespace/fiap-mongodb ;;
    '-n fiap-mongodb delete pvc '*) ${failCleanup ? 'exit 12' : ':'} ;;
  esac`);
  try {
    const result = spawnSync(bash, ['-c', 'export PATH="$STUB_BIN:$PATH"; exec /bin/bash "$STAGE_SCRIPT"'], {
      encoding:'utf8', env:{...process.env, STUB_BIN:shellPath(bin), CALL_LOG:shellPath(log),
        STAGE_SCRIPT:shellPath(fileURLToPath(new URL('./terraform-stage.sh', import.meta.url))),
        STAGE:stage, OPERATION:operation, SOURCE_SHA:'0'.repeat(40),
        RUNNER_TEMP:shellPath(directory), GITHUB_STEP_SUMMARY:shellPath(join(directory, 'summary'))}
    });
    return {...result, calls:readFileSync(log, 'utf8').trim().split(/\r?\n/)};
  } finally { rmSync(directory, {recursive:true, force:true}); }
}

test('destroy descarta PVs retidos, remove PVCs restantes e aguarda EBS antes de prosseguir', () => {
  const result = destroy();
  assert.equal(result.status, 0, result.stderr);
  const apply = result.calls.findIndex(call => call.startsWith('terraform ') && call.includes(' apply '));
  const cleanup = result.calls.findIndex(call => call.startsWith('kubectl -n fiap-mongodb delete pvc '));
  const wait = result.calls.findIndex(call => call.startsWith('aws ec2 wait volume-deleted'));
  assert.ok(apply > 0 && cleanup > apply && wait > cleanup);
  for (const pv of ['pv-kafka', 'pv-mongodb']) {
    const patch = result.calls.findIndex(call => call.startsWith('kubectl patch pv ' + pv + ' '));
    assert.ok(patch > 0 && patch < apply);
    assert.match(result.calls[patch], /persistentVolumeReclaimPolicy.*Delete/);
  }
  assert.ok(result.calls.some(call => call.includes('volume-deleted --volume-ids vol-abcd')));
  assert.ok(result.calls.some(call => call.includes('volume-deleted --volume-ids vol-cdef')));
  assert.ok(!result.calls.some(call => call.startsWith('kubectl -n fiap-messaging delete pvc ')));
});

test('falha na exclusao dos PVCs interrompe destroy e identifica a fase', () => {
  const result = destroy({failCleanup:true});
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /phase=verification/);
  assert.ok(!result.calls.some(call => call.startsWith('aws ec2 wait')));
});

test('volume desconhecido impede alteracao de reclaim e o plano destrutivo', () => {
  const result = destroy({invalidVolume:true});
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Volume EBS invalido/);
  assert.ok(!result.calls.some(call => call.startsWith('kubectl patch')));
  assert.ok(!result.calls.some(call => call.startsWith('terraform ') && call.includes(' plan ')));
});

for (const operation of ['apply', 'destroy']) {
  test(`kubernetes-configs ${operation} seleciona recuperacao apenas no plano destrutivo`, () => {
    const result = destroy({stage:'kubernetes-configs', operation});
    assert.equal(result.status, 0, result.stderr);
    const plan = result.calls.find(call => call.startsWith('terraform ') && call.includes(' plan '));
    assert.ok(plan);
    assert.match(plan, new RegExp('-var=destroy_mode=' + (operation === 'destroy')));
    assert.equal(plan.includes(' -destroy '), operation === 'destroy');
    const apply = result.calls.find(call => call.startsWith('terraform ') && call.includes(' apply '));
    assert.doesNotMatch(apply, /-var=/); // O apply usa somente o plano salvo.
  });
}
