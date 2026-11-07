import {execFileSync} from 'node:child_process';
const run=(command,args)=>execFileSync(command,args,{encoding:'utf8'}).trim();
run('bash',['scripts/platform/install-kubectl.sh']);
run('kubectl',['-n','fiap-observability','rollout','status','deployment/otel-collector','--timeout=5m']);
run('kubectl',['wait','apiservice/v1beta1.metrics.k8s.io','--for=condition=Available','--timeout=3m']);
for(const namespace of ['fiap-os','fiap-execution','fiap-billing']){
 let ready=false;
 for(let attempt=0;attempt<60;attempt++){
  const items=JSON.parse(run('kubectl',['-n',namespace,'get','hpa','-o','json'])).items;
  ready=items.length===1&&['AbleToScale','ScalingActive'].every(type=>items[0].status?.conditions?.some(c=>c.type===type&&c.status==='True'));
  if(ready)break;
  await new Promise(resolve=>setTimeout(resolve,5000));
 }
 if(!ready)throw new Error('HPA sem metricas/condicoes saudaveis: '+namespace);
 console.log(run('kubectl',['-n',namespace,'top','pods']));
}
console.log('Collector pronto, metrics-server disponivel e HPAs saudaveis. Confirmar ingestao no New Relic separadamente.');
