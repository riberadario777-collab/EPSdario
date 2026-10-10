import {useEffect,useState,ReactNode} from 'react'; import {supabase} from '../lib/supabase'
export default function Crud({table,title,fields,cols,actions}:{table:string,title:string,fields:{k:string,l:string,t?:string}[],cols:string[],actions?:(r:any,reload:()=>void)=>ReactNode}){
 const [rows,setRows]=useState<any[]>([]),[f,setF]=useState<any>({}),[err,setErr]=useState('')
 const load=async()=>{const {data}=await supabase.from(table).select('*'+(table==='products'?',inventory(physical)':'')).order('created_at',{ascending:false});setRows(data||[])}
 useEffect(()=>{load()},[table])
 const save=async()=>{const p:any={};fields.forEach(x=>{if(f[x.k]!==undefined&&f[x.k]!=='')p[x.k]=x.t==='number'?Number(f[x.k]):f[x.k]});const {error}=await supabase.from(table).insert(p);setErr(error?.message||'');if(!error){setF({});load()}}
 return <><div className="card"><h3>{title}</h3>{fields.map(x=><input key={x.k} placeholder={x.l} type={x.t||'text'} value={f[x.k]||''} onChange={e=>setF({...f,[x.k]:e.target.value})}/>)}<button className="b" onClick={save}>Guardar</button><span className="err"> {err}</span></div>
 <div className="card tw"><table><thead><tr>{cols.map(c=><th key={c}>{c}</th>)}{actions&&<th/>}</tr></thead><tbody>{rows.map(r=><tr key={r.id}>{cols.map(c=><td key={c}>{c==='stock'?r.inventory?.physical:String(r[c]??'')}</td>)}{actions&&<td>{actions(r,load)}</td>}</tr>)}</tbody></table></div></>
}
