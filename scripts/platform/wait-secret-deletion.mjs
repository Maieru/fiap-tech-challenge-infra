import {execFileSync} from 'node:child_process';
const names={
  'aws-resources':['fiap-secret-manager-jwt-signing-key'],
  'kubernetes-addons':['fiap-newrelic-license'],
  database:['fiap-os-database-credentials','fiap-billing-database-credentials','fiap-execution-database-credentials','fiap-postgres-admin','fiap-documentdb-admin']
}[process.env.STAGE]||[];
for(const name of names){
 let removed=false;
 for(let attempt=0;attempt<120;attempt++){
  try{execFileSync('aws',['secretsmanager','describe-secret','--secret-id',name,'--output','json','--no-cli-pager'],{encoding:'utf8',stdio:['ignore','pipe','pipe']});}
  catch(error){if(String(error.stderr).includes('ResourceNotFoundException')){removed=true;break;}throw error;}
  await new Promise(resolve=>setTimeout(resolve,3000));
 }
 if(!removed)throw new Error('Segredo ainda existe ou aguarda exclusao: '+name+'. Confira o estado antes de recriar.');
}
