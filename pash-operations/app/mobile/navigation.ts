export type Route={tab:string,menu:boolean};
export type BackState=Route&{scanner:boolean,action:boolean,compose:boolean};
export type BackPlan={kind:'scanner'|'action'|'compose'|'route'|'home'|'root',route?:Route};
/** On Android, go back through the UI; never call exitApp. */
export function resolveBack(state:BackState,history:Route[]):BackPlan{
  if(state.scanner)return {kind:'scanner'};
  if(state.action)return {kind:'action'};
  if(state.compose)return {kind:'compose'};
  const previous=history[history.length-1];
  if(previous)return {kind:'route',route:previous};
  if(state.menu||state.tab!=='dashboard')return {kind:'home'};
  return {kind:'root'};
}
