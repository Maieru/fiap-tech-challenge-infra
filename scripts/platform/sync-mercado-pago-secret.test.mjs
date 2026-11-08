import assert from 'node:assert/strict';
import {test} from 'node:test';
import {existsSync, readFileSync, mkdtempSync, rmSync, readdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {credentials, syncSecret} from './sync-mercado-pago-secret.mjs';

const environment = {MERCADO_PAGO_ACCESS_TOKEN: 'test-access', MERCADO_PAGO_WEBHOOK_SECRET: 'test-webhook'};
test('exige ambos os secrets antes de alterar AWS', () => {
  assert.throws(() => credentials({}), /MERCADO_PAGO_ACCESS_TOKEN/);
  assert.throws(() => credentials({MERCADO_PAGO_ACCESS_TOKEN: 'token'}), /MERCADO_PAGO_WEBHOOK_SECRET/);
});
for (const failure of [false, true]) {
  test('envia JSON por arquivo e remove o temporario, falha=' + failure, () => {
    const root = mkdtempSync(join(tmpdir(), 'secret-test-'));
    let file;
    try {
      const run = (command, args, options) => {
        assert.equal(command, 'aws');
        assert.equal(args[args.indexOf('--secret-id') + 1], 'fiap-billing-mercadopago-credentials');
        assert(!args.join(' ').includes(environment.MERCADO_PAGO_ACCESS_TOKEN));
        assert(!args.join(' ').includes(environment.MERCADO_PAGO_WEBHOOK_SECRET));
        file = args[args.indexOf('--secret-string') + 1].slice('file://'.length);
        assert.deepEqual(JSON.parse(readFileSync(file, 'utf8')), {MercadoPago__AccessToken: 'test-access', MercadoPago__WebhookSecret: 'test-webhook'});
        assert.equal(options.stdio[1], 'ignore');
        if (failure) throw new Error('provider error with sensitive details');
      };
      if (failure) assert.throws(() => syncSecret(environment, run, root), {message: 'Falha ao sincronizar a credencial Mercado Pago no Secrets Manager.'});
      else syncSecret(environment, run, root);
      assert.equal(existsSync(file), false);
      assert.deepEqual(readdirSync(root), []);
    } finally { rmSync(root, {recursive: true, force: true}); }
  });
}
