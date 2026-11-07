// Integração real e isolada: Docker, TLS, autenticação, transações e reinício.
// EXECUTION_TEST_IMAGE opcional executa também --verify-persistence da imagem da API.
import {execFileSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';

const id = 'fiap-mongo-test-' + randomBytes(5).toString('hex');
const directory = mkdtempSync(join(tmpdir(), id));
const scripts = fileURLToPath(new URL('../../k8s/mongodb/scripts', import.meta.url));
const host = 'mongodb-0.mongodb.fiap-mongodb.svc.cluster.local';
const image = 'mongo:8.0@sha256:b9924c330a8bbc5800fe9c69f04a84e221eca7b28fd049a0354147d9908fa142';
const password = randomBytes(24).toString('hex');
const environment = {...process.env, MONGO_ADMIN_USERNAME:'fiap_admin', MONGO_ADMIN_PASSWORD:password,
  MONGO_REPLICA_HOST:host + ':27017', ADMIN_USERNAME:'fiap_admin', ADMIN_PASSWORD:password,
  MONGODB_HOST:host, EXECUTION_PASSWORD:randomBytes(24).toString('hex')};
const docker = (args, input) => execFileSync('docker', args, {encoding:'utf8', input, env:environment, timeout:120000, stdio:['pipe','pipe','pipe']});
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const shell = script => docker(['exec','-i',id,'mongosh','--nodb','--quiet','--file','/dev/stdin'], script);
const uri = `mongodb://fiap_admin:${password}@${host}:27017/admin?authSource=admin&tls=true&tlsCAFile=/security/ca_pem&replicaSet=rs0`;
const authenticated = body => shell(`const admin = new Mongo(${JSON.stringify(uri)}).getDB('admin');\n${body}`);
const start = () => docker(['run','-d','--name',id,'--network',id,'--network-alias',host,'--network-alias','wrong.mongodb.test','--user','999:999',
  '--env','MONGO_ADMIN_USERNAME','--env','MONGO_ADMIN_PASSWORD','--env','MONGO_REPLICA_HOST',
  '--mount',`type=volume,source=${id}-security,target=/security,readonly`,
  '--mount',`type=volume,source=${id}-data,target=/data/db`,
  '--mount',`type=bind,source=${resolve(scripts)},target=/scripts,readonly`,
  '--entrypoint','/bin/sh',image,'/scripts/start.sh']);
async function ready() {
  for (let attempt=0; attempt<90; attempt++) {
    if (docker(['inspect','--format','{{.State.Running}}',id]).trim() !== 'true')
      throw new Error('MongoDB encerrou: ' + docker(['logs','--tail','100',id]).replaceAll(password,'[redacted]'));
    try {
      docker(['exec',id,'mongosh','--nodb','--quiet','/scripts/health.js']);
      // Readiness/hello sozinho não comprova que a criação do primeiro usuário terminou.
      authenticated('if (admin.runCommand({connectionStatus:1}).authInfo.authenticatedUsers.length !== 1) quit(1);');
      return;
    } catch { await sleep(1000); }
  }
  throw new Error('MongoDB não inicializou dentro do prazo.');
}
try {
  docker(['network','create',id]);
  docker(['volume','create',id+'-security']);
  docker(['volume','create',id+'-data']);
  docker(['run','--rm','--mount',`type=volume,source=${id}-security,target=/security`,
    '--mount',`type=volume,source=${id}-data,target=/data/db`,'--entrypoint','/bin/sh',image,'-ec',`
    cd /security
    openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca_pem -days 2 -subj '/CN=MongoDB Integration CA' >/dev/null 2>&1
    openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj '/CN=${host}' >/dev/null 2>&1
    printf 'subjectAltName=DNS:${host},DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth,clientAuth\n' > extensions
    openssl x509 -req -in server.csr -CA ca_pem -CAkey ca.key -CAcreateserial -out server.crt -days 1 -extfile extensions >/dev/null 2>&1
    cat server.key server.crt > server_pem
    openssl rand -base64 72 > keyfile
    chown -R 999:999 /security /data/db
    chmod 400 /security/keyfile /security/server_pem
    chmod 444 /security/ca_pem
    cp /security/ca_pem /security/ca.pem
  `]);
  start();
  await ready();
  authenticated(`
    const session = admin.getMongo().startSession();
    const test = session.getDatabase('fiap_execution');
    test.marker.createIndex({name:1}, {unique:true});
    session.startTransaction();
    test.marker.insertOne({name:'committed'});
    session.commitTransaction();
    session.startTransaction();
    test.marker.insertOne({name:'rolled-back'});
    session.abortTransaction();
    if (test.marker.countDocuments({}) !== 1) throw new Error('Commit/rollback incorretos.');
    session.endSession();
  `);
  const anonymous = shell(`const database = new Mongo('mongodb://localhost:27017/fiap_execution?tls=true&tlsCAFile=/security/ca_pem&directConnection=true').getDB('fiap_execution'); try { database.runCommand({find:'marker',filter:{}}); throw new Error('Acesso anônimo permitido.'); } catch (error) { if (error.code !== 13) throw error; print(error.code); }`);
  assert.match(anonymous, /13/);
  const noTls = docker(['exec',id,'mongosh','--nodb','--quiet','--eval',
    'try { new Mongo("mongodb://localhost:27017/?directConnection=true&serverSelectionTimeoutMS=2000").getDB("admin").runCommand({ping:1}); quit(1); } catch { print("TLS required"); }']);
  assert.match(noTls, /TLS required/);
  const wrongHostname = shell(`try { new Mongo('mongodb://wrong.mongodb.test:27017/?tls=true&tlsCAFile=/security/ca_pem&directConnection=true&serverSelectionTimeoutMS=2000').getDB('admin').runCommand({ping:1}); throw new Error('Hostname inválido aceito.'); } catch (error) { if (error.message === 'Hostname inválido aceito.') throw error; print('Hostname rejected'); }`);
  assert.match(wrongHostname, /Hostname rejected/);
  const userScript = fileURLToPath(new URL('../../../FiapTechChallengeDb/scripts/platform/mongodb.js', import.meta.url));
  // Execute o script real de grants duas vezes, a partir do repositório DB irmão.
  for (let attempt=0; attempt<2; attempt++) docker(['run','--rm','--network',id,
    '--env','ADMIN_USERNAME','--env','ADMIN_PASSWORD','--env','MONGODB_HOST','--env','EXECUTION_PASSWORD',
    '--mount',`type=volume,source=${id}-security,target=/mongo-certs,readonly`,
    '--mount',`type=bind,source=${userScript},target=/initialize.js,readonly`,
    '--entrypoint','mongosh',image,'--nodb','--quiet','/initialize.js']);
  docker(['stop','--time','20',id]);
  docker(['rm',id]);
  start();
  await ready();
  assert.match(authenticated(`print(admin.getSiblingDB('fiap_execution').marker.countDocuments({name:'committed'}));`), /1/);
  if (process.env.EXECUTION_TEST_IMAGE) {
    const ca = docker(['exec',id,'cat','/security/ca_pem']);
    writeFileSync(join(directory,'ca.pem'),ca);
    const connection = uri.replace('/admin?', '/fiap_compat_tls_test?').replace('&tlsCAFile=/security/ca_pem','');
    environment.Mongo__ConnectionString = connection;
    docker(['run','--rm','--network',id,'--env','Mongo__ConnectionString',
      '--env','Mongo__DatabaseName=fiap_compat_tls_test','--env','Mongo__UseDocumentDb=false',
      '--env','Mongo__CaCertificatePath=/certs/ca.pem',
      '--mount',`type=bind,source=${directory},target=/certs,readonly`,process.env.EXECUTION_TEST_IMAGE,'--verify-persistence']);
    assert.match(authenticated(`print(admin.getSiblingDB('fiap_compat_tls_test').getCollectionNames().length);`), /0/);
    console.log('Execution --verify-persistence com TLS e limpeza do banco temporário aprovados.');
  }
  console.log('MongoDB: TLS obrigatório, autenticação, grants idempotentes/isolados, commit, rollback e persistência após reinício aprovados.');
} finally {
  for (const args of [['rm','-f',id],['volume','rm',id+'-security',id+'-data'],['network','rm',id]]) {
    try { docker(args); } catch { /* Não oculta o erro original; nomes são exclusivos deste ensaio. */ }
  }
  assert.equal(dirname(directory),resolve(tmpdir()));
  rmSync(directory,{recursive:true,force:true});
}
