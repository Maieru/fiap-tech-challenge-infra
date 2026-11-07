import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';

// Seleciona somente estado/causas; não imprime specs, env, dados de Secrets ou logs dos agentes.
export function summarize(resource) {
  const conditions = (resource.status?.conditions || []).map(({type,status,reason,message}) => ({type,status,reason,message}));
  const containers = (resource.status?.containerStatuses || []).map(container => ({
    name:container.name, ready:container.ready, restarts:container.restartCount,
    waiting:container.state?.waiting,
    terminated:container.state?.terminated && {reason:container.state.terminated.reason,exitCode:container.state.terminated.exitCode}
  }));
  return {kind:resource.kind, name:resource.metadata?.name, phase:resource.status?.phase,
    conditions, containers, readyReplicas:resource.status?.readyReplicas,
    desiredNumberScheduled:resource.status?.desiredNumberScheduled, numberReady:resource.status?.numberReady,
    allocatable:resource.status?.allocatable,
    ...(resource.kind === 'Event' ? {reason:resource.reason,message:resource.message,object:resource.involvedObject?.name} : {})};
}

export function diagnosticNamespaces(stage) {
  if (stage === 'kubernetes-configs') return ['fiap-observability'];
  if (stage === 'messaging') return ['fiap-messaging','fiap-mongodb'];
  throw new Error('Estagio de diagnostico invalido.');
}

function inspect(args) {
  const result = spawnSync('kubectl',[...args,'--request-timeout=10s','-o','json'],{encoding:'utf8',timeout:60000});
  if (result.error || result.status !== 0) {
    console.error('Falha ao consultar diagnostico: ' + (result.error?.message || result.stderr));
    process.exitCode = 1;
    return;
  }
  const items = JSON.parse(result.stdout).items || [];
  for (const item of items.slice(-60)) console.log(JSON.stringify(summarize(item)));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  for (const namespace of diagnosticNamespaces(process.env.STAGE || 'kubernetes-configs')) {
    console.log('Diagnostico Kubernetes: ' + namespace);
    inspect(['-n',namespace,'get','pods,deployments,daemonsets,statefulsets,jobs,persistentvolumeclaims,externalsecrets,secretstores']);
    // Events sobrevivem ao rollback e preservam falhas de scheduling/pull/Secret/volumes.
    inspect(['-n',namespace,'get','events','--sort-by=.lastTimestamp']);
  }
  inspect(['get','nodes']);
}
