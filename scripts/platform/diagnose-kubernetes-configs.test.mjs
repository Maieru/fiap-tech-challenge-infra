import {test} from 'node:test';
import assert from 'node:assert/strict';
import {summarize} from './diagnose-kubernetes-configs.mjs';

test('diagnostico preserva causa de scheduling sem divulgar env ou Secret', () => {
  const result = summarize({kind:'Pod',metadata:{name:'newrelic-agent'},
    spec:{containers:[{env:[{name:'NRIA_LICENSE_KEY',value:'private-license'}]}]},
    data:{'license-key':'private-license'},status:{phase:'Pending',
      conditions:[{type:'PodScheduled',status:'False',reason:'Unschedulable',message:'Insufficient memory'}],
      containerStatuses:[{name:'agent',ready:false,restartCount:0,state:{waiting:{reason:'CreateContainerConfigError',message:'secret not found'}}}]
    }});
  assert.equal(result.conditions[0].message,'Insufficient memory');
  assert.equal(result.containers[0].waiting.reason,'CreateContainerConfigError');
  assert.ok(!JSON.stringify(result).includes('private-license'));
  assert.ok(!('spec' in result));
  assert.ok(!('data' in result));
});

test('eventos continuam identificando falhas depois do rollback Helm', () => {
  const result = summarize({kind:'Event',metadata:{name:'failed'},reason:'FailedScheduling',
    message:'0/3 nodes are available',involvedObject:{name:'newrelic-agent'}});
  assert.equal(result.reason,'FailedScheduling');
  assert.equal(result.object,'newrelic-agent');
});
