import {execFileSync} from 'node:child_process';
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

export function credentials(environment) {
  const value = {};
  for (const [name, property] of [['MERCADO_PAGO_ACCESS_TOKEN', 'MercadoPago__AccessToken'], ['MERCADO_PAGO_WEBHOOK_SECRET', 'MercadoPago__WebhookSecret']]) {
    if (!environment[name]?.trim()) throw new Error('Configure o secret ' + name + '.');
    value[property] = environment[name].trim();
  }
  return value;
}

export function syncSecret(environment = process.env, run = execFileSync, temporaryRoot = tmpdir()) {
  const value = credentials(environment);
  const directory = mkdtempSync(join(temporaryRoot, 'fiap-mercadopago-'));
  const file = join(directory, 'credentials.json');
  try {
    writeFileSync(file, JSON.stringify(value), {mode: 0o600});
    run('aws', ['secretsmanager', 'put-secret-value', '--secret-id', 'fiap-billing-mercadopago-credentials',
      '--secret-string', 'file://' + file, '--no-cli-pager'], {stdio: ['ignore', 'ignore', 'pipe']});
  } catch {
    throw new Error('Falha ao sincronizar a credencial Mercado Pago no Secrets Manager.');
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv[2] === '--validate') credentials(process.env);
  else syncSecret();
}
