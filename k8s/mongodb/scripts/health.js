const admin = new Mongo('mongodb://localhost:27017/admin?tls=true&tlsCAFile=/security/ca_pem&directConnection=true&serverSelectionTimeoutMS=2000').getDB('admin');
const status = admin.hello();
quit(status.isWritablePrimary && status.setName === 'rs0' ? 0 : 1);
