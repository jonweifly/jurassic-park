// Pass installed gltf-validator module path (bundled with @gltf-transform/cli).
const fs = require('node:fs');
const path = require('node:path');
const validator = require(process.argv[2]);
const root = path.resolve(__dirname,'../..');
(async () => {
 const dir=path.resolve(root,process.argv[3] || 'godot/assets/models');
 const results=[];
 for (const name of fs.readdirSync(dir).filter(n=>n.endsWith('.glb')).sort()) {
  const result=await validator.validateBytes(new Uint8Array(fs.readFileSync(path.join(dir,name))),{
   uri:name, externalResourceFunction:async uri=>new Uint8Array(fs.readFileSync(path.resolve(dir,decodeURIComponent(uri))))
  });
  results.push({name,errors:result.issues.numErrors,warnings:result.issues.numWarnings,messages:result.issues.messages});
 }
 fs.writeFileSync(path.resolve(root,process.argv[4] || 'art/validation-khronos.json'),JSON.stringify(results,null,2)+'\n');
 console.log(`KHRONOS: ${results.length} assets, ${results.reduce((n,r)=>n+r.errors,0)} errors, ${results.reduce((n,r)=>n+r.warnings,0)} warnings`);
 process.exitCode=results.some(r=>r.errors>0)?1:0;
})();
