import {useEffect,useState} from 'react'; import {supabase} from '../lib/supabase'
export default function PriceLists(){
 const [ls,setLs]=useState<any[]>([]),[pr,setPr]=useState<any[]>([]),[cl,setCl]=useState<any[]>([]),[it,setIt]=useState<any[]>([]),[nn,setNn]=useState(''),[l,setL]=useState(''),[p,setP]=useState(''),[v,setV]=useState(''),[c,setC]=useState(''),[msg,setMsg]=useState('')
 const load=async()=>{setLs((await supabase.from('price_lists').select('*')).data||[]);setPr((await supabase.from('products').select('id,code,price_m3')).data||[]);setCl((await supabase.from('clients').select('id,name,price_list_id')).data||[]);setIt((await supabase.from('price_list_items').select('*,price_lists(name),products(code)')).data||[])}
 useEffect(()=>{load()},[])
 const r=async(pm:any)=>{const {error}=await pm;setMsg(error?error.message:'Guardado');load()}
 return <><div className="card"><h3>Listas de precios (solo administrador)</h3><input placeholder="Nueva lista" value={nn} onChange={e=>setNn(e.target.value)}/><button className="b" onClick={()=>r(supabase.from('price_lists').insert({name:nn}))}>Crear</button><span className="err"> {msg}</span><br/>
 <select value={l} onChange={e=>setL(e.target.value)}><option value="">Lista…</option>{ls.map(x=><option key={x.id} value={x.id}>{x.name}</option>)}</select><select value={p} onChange={e=>setP(e.target.value)}><option value="">Producto…</option>{pr.map(x=><option key={x.id} value={x.id}>{x.code} (base {x.price_m3})</option>)}</select><input type="number" placeholder="Bs/m³" value={v} onChange={e=>setV(e.target.value)}/>
 <button className="b" onClick={()=>r(supabase.from('price_list_items').upsert({list_id:l,product_id:p,price_m3:Number(v)},{onConflict:'list_id,product_id'}))}>Fijar precio</button><br/>
 <select value={c} onChange={e=>setC(e.target.value)}><option value="">Cliente…</option>{cl.map(x=><option key={x.id} value={x.id}>{x.name}</option>)}</select><button className="b" onClick={()=>r(supabase.from('clients').update({price_list_id:l||null}).eq('id',c))}>Asignar lista elegida al cliente</button></div>
 <div className="card tw"><table><thead><tr><th>Lista</th><th>Producto</th><th>Bs/m³</th></tr></thead><tbody>{it.map(x=><tr key={x.id}><td>{x.price_lists?.name}</td><td>{x.products?.code}</td><td>{x.price_m3}</td></tr>)}</tbody></table></div></>
}
