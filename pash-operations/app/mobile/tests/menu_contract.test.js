const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const ts=require('typescript');

test('every PASH Operations workspace has a display label before login can render the menu',()=>{
  const code=fs.readFileSync(path.join(__dirname,'..','App.tsx'),'utf8');
  const source=ts.createSourceFile('App.tsx',code,ts.ScriptTarget.Latest,true,ts.ScriptKind.TSX);
  const found=new Map();
  function visit(node){
    if(ts.isVariableDeclaration(node)&&ts.isIdentifier(node.name)&&['MENU','LABELS','categories'].includes(node.name.text)){
      assert.ok(node.initializer&&ts.isObjectLiteralExpression(node.initializer),'Expected workspace object '+node.name.text);
      found.set(node.name.text,node.initializer);
    }
    ts.forEachChild(node,visit);
  }
  visit(source);
  for(const name of ['MENU','LABELS','categories'])assert.ok(found.has(name),'Missing '+name);
  function nameOf(prop){return (ts.isIdentifier(prop.name)||ts.isStringLiteral(prop.name))?prop.name.text:null;}
  const menu=new Set(found.get('MENU').properties.map(nameOf).filter(Boolean));
  const labels=new Set(found.get('LABELS').properties.map(nameOf).filter(Boolean));
  const missing=[...menu].filter(x=>!labels.has(x));
  assert.deepEqual(missing,[],'A missing label will crash signed-in employee navigation');
  for(const group of found.get('categories').properties){
    if(!ts.isPropertyAssignment(group)||!ts.isArrayLiteralExpression(group.initializer))continue;
    for(const item of group.initializer.elements){
      assert.ok(ts.isStringLiteral(item),'Category workspaces must be literal keys');
      assert.ok(menu.has(item.text),'Undefined MENU category: '+item.text);
      assert.ok(labels.has(item.text),'Missing category label: '+item.text);
    }
  }
});
