import {execFileSync} from 'node:child_process';
const run=(command,args)=>execFileSync(command,args,{encoding:'utf8'}).trim();
const aws=(...args)=>JSON.parse(run('aws',[...args,'--output','json','--no-cli-pager']));
let cluster;
try{cluster=aws('eks','describe-cluster','--name','fiap-eks-cluster').cluster;}
catch(error){if(String(error.stderr).includes('ResourceNotFoundException')) process.exit(0);throw error;}
if(cluster.status!=='ACTIVE') throw new Error('Cluster nao esta ACTIVE; retome a limpeza quando estiver acessivel.');
run('bash',['scripts/platform/install-kubectl.sh']);
let alb;
try{alb=aws('elbv2','describe-load-balancers','--names','fiap-internal-edge').LoadBalancers[0].LoadBalancerArn;}
catch(error){if(!String(error.stderr).includes('LoadBalancerNotFound'))throw error;}
for(const namespace of ['fiap-os','fiap-execution','fiap-billing','fiap-frontend']){
 if(!run('kubectl',['get','namespace',namespace,'--ignore-not-found=true','-o','name'])) continue;
 run('kubectl',['-n',namespace,'delete','ingress','--all','--ignore-not-found=true','--wait=true','--timeout=10m']);
 run('kubectl',['-n',namespace,'delete','deployment,hpa,job','--all','--ignore-not-found=true','--wait=true','--timeout=10m']);
 for(let attempt=0;attempt<90;attempt++){
  const pods=JSON.parse(run('kubectl',['-n',namespace,'get','pods','-o','json'])).items;
  if(!pods.length)break;
  if(attempt===89)throw new Error('Pods ainda ativos em '+namespace);
  await new Promise(resolve=>setTimeout(resolve,5000));
 }
}
if(alb) run('aws',['elbv2','wait','load-balancers-deleted','--load-balancer-arns',alb]);
console.log('Aplicacoes e ALB removidos.');
