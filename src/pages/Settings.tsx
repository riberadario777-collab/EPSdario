import {useEffect,useState} from 'react'; import {supabase} from '../lib/supabase'
export default function Settings(){
 const [n,setN]=useState(''),[i,setI]=useState(''),[d,setD]=useState('5'),[m,setM]=useState('')
 useEffect(()=>{supabase.from('company_settings').select('*').single().then(({data})=>{setN(data?.name||'');setI(data?.info||'');setD(String(data?.max_discount??5))})},[])
 return <div className="card"><h3>Datos de la empresa y parámetros</h3><input value={n} onChange={e=>setN(e.target.value)}/><input style={{width:320}} value={i} onChange={e=>setI(e.target.value)}/><br/>
 <label>Descuento máximo para Ventas (%): <input type="number" style={{width:80}} value={d} onChange={e=>setD(e.target.value)}/></label>
 <button className="b" onClick={async()=>{const {error}=await supabase.from('company_settings').update({name:n,info:i,max_discount:Number(d)}).eq('id',1);setM(error?error.message:'Guardado')}}>Guardar</button> <span className="err">{m}</span></div>
}
