const options = '?authSource=admin&tls=true&tlsCAFile=/security/ca_pem&directConnection=true&serverSelectionTimeoutMS=5000';
const credentials = encodeURIComponent(process.env.MONGO_ADMIN_USERNAME) + ':' + encodeURIComponent(process.env.MONGO_ADMIN_PASSWORD);
let admin;
let authenticated = true;
try {
  admin = new Mongo('mongodb://' + credentials + '@localhost:27017/admin' + options).getDB('admin');
  admin.runCommand({connectionStatus: 1});
} catch (error) {
  if (error.code !== 18) throw error;
  authenticated = false;
  // MongoDB permite iniciar o replica set/criar o primeiro usuário somente via localhost.
  admin = new Mongo('mongodb://localhost:27017/admin' + options).getDB('admin');
}
try {
  admin.adminCommand({replSetGetStatus: 1});
} catch (error) {
  if (error.code !== 94) throw error;
  const result = admin.adminCommand({replSetInitiate: {
    _id: 'rs0', members: [{_id: 0, host: process.env.MONGO_REPLICA_HOST}]
  }});
  if (result.ok !== 1) throw new Error('Não foi possível iniciar o replica set.');
}
let primary = false;
for (let attempt = 0; attempt < 60; attempt++) {
  if (admin.hello().isWritablePrimary) { primary = true; break; }
  sleep(1000);
}
if (!primary) throw new Error('MongoDB não elegeu um primário.');
if (!authenticated) {
  admin.createUser({user: process.env.MONGO_ADMIN_USERNAME, pwd: process.env.MONGO_ADMIN_PASSWORD,
    roles: [{role: 'root', db: 'admin'}]});
}
print('Replica set rs0 e administrador MongoDB prontos.');
