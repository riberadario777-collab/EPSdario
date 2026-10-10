import {useEffect,useState} from 'react'; import {supabase} from '../lib/supabase'
const ROLES=['sin_rol','administrador','ventas','despacho','almacen','contabilidad']
export default function Users(){
 const [rows,setRows]=useState<any[]>([]),[msg,setMsg]=useState('')
 const load=async()=>setRows((await supabase.from('profiles').select('*').order('full_name')).data||[])
 useEffect(()=>{load()},[])
 const upd=async(id:string,patch:any)=>{const {error}=await supabase.from('profiles').update(patch).eq('id',id);setMsg(error?error.message:'Guardado');load()}
 return <div className="card tw"><h3>Usuarios y roles</h3><p>Las personas se registran en la pantalla de acceso; aquí les asigna el rol.</p><span className="err">{msg}</span>
 <table><thead><tr><th>Usuario</th><th>Rol</th><th>Activo</th></tr></thead><tbody>{rows.map(r=><tr key={r.id}><td>{r.full_name}</td>
 <td><select value={r.role} onChange={e=>upd(r.id,{role:e.target.value})}>{ROLES.map(x=><option key={x}>{x}</option>)}</select></td>
 <td><input type="checkbox" checked={r.active} onChange={e=>upd(r.id,{active:e.target.checked})}/></td></tr>)}</tbody></table></div>
}
