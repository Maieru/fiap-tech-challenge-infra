import {execFileSync} from 'node:child_process';
const aws=(...args)=>JSON.parse(execFileSync('aws',[...args,'--output','json','--no-cli-pager'],{encoding:'utf8'}));
const rds=aws('rds','describe-db-instances').DBInstances.filter(db=>db.DBInstanceIdentifier.startsWith('fiap-')).map(db=>db.DBInstanceIdentifier);
const documentdb=aws('docdb','describe-db-clusters').DBClusters.filter(db=>db.DBClusterIdentifier.startsWith('fiap-')).map(db=>db.DBClusterIdentifier);
if(rds.length||documentdb.length)throw new Error('Bancos da solucao ainda existem; conferir estados/inventario: '+[...rds,...documentdb].join(', '));
console.log('Remocao de RDS e DocumentDB verificada.');
