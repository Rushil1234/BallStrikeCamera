// Full-course terrain: real polygon shapes from pinchbrook.json drive the
// surface map (pip-tested at 4m resolution so the layout matches the course
// map exactly), analytic FBM noise drives the height field, and TrueCarry_Sim's
// vertex-color + photo-texture splat material handles the visuals.

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { Water }           from 'three/addons/objects/Water.js';
import { makeFbm, makeRng } from './noise.js';

// ---------- Surface constants ----------
export const SURF = {
  ROUGH:    'rough',
  FAIRWAY:  'fairway',
  GREEN:    'green',
  BUNKER:   'bunker',
  WATER:    'water',
  CARTPATH: 'cartpath',
  OOB:      'oob',
};
export const SURF_PROPS = {
  [SURF.ROUGH]:    { restitution:0.22, friction:0.72, spin:0.45, run:0.5  },
  [SURF.FAIRWAY]:  { restitution:0.32, friction:0.58, spin:0.82, run:1.6  },
  [SURF.GREEN]:    { restitution:0.18, friction:0.88, spin:1.00, run:1.0  },
  [SURF.BUNKER]:   { restitution:0.03, friction:0.95, spin:0.40, run:0.2  },
  [SURF.WATER]:    { restitution:0.00, friction:1.00, spin:0.00, run:0.0  },
  [SURF.CARTPATH]: { restitution:0.55, friction:0.35, spin:0.20, run:3.5  },
  [SURF.OOB]:      { restitution:0.20, friction:0.70, spin:0.40, run:0.5  },
};

// ---------- Math helpers ----------
const sstep = (e0,e1,x) => { const t=Math.min(Math.max((x-e0)/(e1-e0),0),1); return t*t*(3-2*t); };
const lerp  = (a,b,t) => a+(b-a)*t;

// Point-in-polygon (ray-casting)
function pip(px, pz, poly) {
  let inside = false;
  for (let i=0, j=poly.length-1; i<poly.length; j=i++) {
    const [xi,zi]=poly[i], [xj,zj]=poly[j];
    if ((zi>pz)!==(zj>pz) && px<((xj-xi)*(pz-zi))/(zj-zi)+xi) inside=!inside;
  }
  return inside;
}

// Paint a polyline corridor as pip-testable quads
function paintPath(pts, halfWidth, paint) {
  if (!pts || pts.length<2) return;
  for (let i=0;i<pts.length-1;i++) {
    const [ax,az]=pts[i],[bx,bz]=pts[i+1];
    const dx=bx-ax,dz=bz-az,len=Math.hypot(dx,dz)||1;
    const nx=dz/len,nz=-dx/len;
    const corridor=[
      [ax+nx*halfWidth, az+nz*halfWidth],
      [bx+nx*halfWidth, bz+nz*halfWidth],
      [bx-nx*halfWidth, bz-nz*halfWidth],
      [ax-nx*halfWidth, az-nz*halfWidth],
    ];
    paint(corridor);
  }
}

// Ellipse value (for smooth height blending only — NOT used for surface type)
function ellipseVal(cx,cz,rx,rz, x,z) {
  return ((x-cx)/rx)**2 + ((z-cz)/rz)**2;
}

// Distance from point to polyline segment
function pathDist(path, x, z) {
  let best=Infinity;
  for (let i=0;i<path.length-1;i++) {
    const [ax,az]=path[i],[bx,bz]=path[i+1];
    const abx=bx-ax,abz=bz-az,L2=abx*abx+abz*abz;
    const t=L2?Math.min(Math.max(((x-ax)*abx+(z-az)*abz)/L2,0),1):0;
    best=Math.min(best,Math.hypot(x-ax-abx*t,z-az-abz*t));
  }
  return best;
}

// ---------- Surface map: pip() against real OSM polygons ----------
// Pre-built at 4m resolution once at load; O(1) lookup per terrain vertex.
const SMAP = { ROUGH:0, FAIRWAY:1, GREEN:2, BUNKER:3, WATER:4, CARTPATH:5 };
const SMAP_TO_SURF = [SURF.ROUGH,SURF.FAIRWAY,SURF.GREEN,SURF.BUNKER,SURF.WATER,SURF.CARTPATH];

function buildSurfaceMap(courseData, originX, originZ, width, depth) {
  const RES = 4;
  const cols = Math.ceil(width/RES)+1;
  const rows = Math.ceil(depth/RES)+1;
  const grid = new Uint8Array(cols*rows); // default 0 = ROUGH

  function paintPoly(poly, val) {
    if (!poly||poly.length<3) return;
    const xs=poly.map(p=>p[0]),zs=poly.map(p=>p[1]);
    const minXi=Math.max(0,Math.floor((Math.min(...xs)-originX)/RES));
    const maxXi=Math.min(cols-1,Math.ceil((Math.max(...xs)-originX)/RES));
    const minZi=Math.max(0,Math.floor((Math.min(...zs)-originZ)/RES));
    const maxZi=Math.min(rows-1,Math.ceil((Math.max(...zs)-originZ)/RES));
    for (let r=minZi;r<=maxZi;r++) for(let c=minXi;c<=maxXi;c++) {
      if (pip(originX+c*RES, originZ+r*RES, poly)) grid[r*cols+c]=val;
    }
  }

  // Water first (lowest priority — playable surfaces paint on top)
  for (const w of (courseData.globalWater||[])) paintPoly(w, SMAP.WATER);
  for (const h of courseData.holes) for (const w of (h.water||[])) paintPoly(w, SMAP.WATER);
  // Fairways + tees (tees are cut like fairways)
  for (const h of courseData.holes) paintPoly(h.fairway, SMAP.FAIRWAY);
  for (const h of courseData.holes) if (h.teePolygon) paintPoly(h.teePolygon, SMAP.FAIRWAY);
  // Bunkers over fairways
  for (const h of courseData.holes) for (const b of (h.bunkers||[])) paintPoly(b, SMAP.BUNKER);
  // Greens over everything
  for (const h of courseData.holes) paintPoly(h.green.polygon, SMAP.GREEN);
  // Cart paths on top
  for (const path of (courseData.cartPaths||[])) {
    paintPath(path, 1.8, corridor => paintPoly(corridor, SMAP.CARTPATH));
  }

  function surfaceAt(x, z) {
    const c=Math.round((x-originX)/RES), r=Math.round((z-originZ)/RES);
    if (c<0||c>=cols||r<0||r>=rows) return SURF.OOB;
    return SMAP_TO_SURF[grid[r*cols+c]];
  }
  return { surfaceAt, grid, cols, rows, RES };
}

// ---------- Analytic height field ----------
function buildHeightField(courseData) {
  const fbmBase   = makeFbm(7, 4);
  const fbmDetail = makeFbm(31, 3);
  const fbmGreen  = makeFbm(53, 3);

  // Per-hole: green centroid + bunker centroids for bowl carving
  const holes = courseData.holes.map(hole => {
    const gp = hole.green.polygon;
    const gcx = gp ? gp.reduce((a,p)=>a+p[0],0)/gp.length : hole.green.center[0];
    const gcz = gp ? gp.reduce((a,p)=>a+p[1],0)/gp.length : hole.green.center[1];
    const grx = gp ? (Math.max(...gp.map(p=>p[0]))-Math.min(...gp.map(p=>p[0])))/2+2 : 15;
    const grz = gp ? (Math.max(...gp.map(p=>p[1]))-Math.min(...gp.map(p=>p[1])))/2+2 : 15;

    const bunkers = (hole.bunkers||[]).map((poly,bi) => {
      const bx=poly.reduce((a,p)=>a+p[0],0)/poly.length;
      const bz=poly.reduce((a,p)=>a+p[1],0)/poly.length;
      const rx=(Math.max(...poly.map(p=>p[0]))-Math.min(...poly.map(p=>p[0])))/2+1;
      const rz=(Math.max(...poly.map(p=>p[1]))-Math.min(...poly.map(p=>p[1])))/2+1;
      const depth=(hole.bunkerDepths||[])[bi]||1.0;
      return {bx,bz,rx,rz,depth};
    });

    return { tee:hole.tee, path:hole.path, gcx,gcz,grx,grz, bunkers };
  });

  // Water: ellipse centroids for carving
  const waters = (courseData.globalWater||[]).map(poly => {
    const cx=poly.reduce((a,p)=>a+p[0],0)/poly.length;
    const cz=poly.reduce((a,p)=>a+p[1],0)/poly.length;
    const rx=(Math.max(...poly.map(p=>p[0]))-Math.min(...poly.map(p=>p[0])))/2;
    const rz=(Math.max(...poly.map(p=>p[1]))-Math.min(...poly.map(p=>p[1])))/2;
    const base=fbmBase(cx*0.006,cz*0.006)*5.0+fbmBase(cx*0.018+50,cz*0.018)*1.2;
    return {cx,cz,rx:rx+8,rz:rz+8,level:base-1.2};
  });

  function heightAt(x, z) {
    let h = fbmBase(x*0.006,z*0.006)*5.0
           + fbmBase(x*0.018+50,z*0.018)*1.2
           + fbmDetail(x*0.05,z*0.05)*0.5;

    for (const p of holes) {
      const [tx,tz]=p.tee;

      // Tee pad: level disc
      const td=Math.hypot(x-tx,z-tz);
      if (td<14) {
        const teeH=fbmBase(tx*0.006,tz*0.006)*5.0+fbmBase(tx*0.018+50,tz*0.018)*1.2+0.45;
        h=lerp(h,teeH,1-sstep(7,13,td));
      }

      // Fairway crown (smooth, path-based)
      const dist=pathDist(p.path,x,z);
      if (dist<60) h+=sstep(55,5,dist)*0.18;

      // Green plateau + undulation
      const gv=ellipseVal(p.gcx,p.gcz,p.grx+10,p.grz+10,x,z);
      if (gv<3.5) {
        const greenH=fbmBase(p.gcx*0.006,p.gcz*0.006)*5.0+fbmBase(p.gcx*0.018+50,p.gcz*0.018)*1.2
          +0.45+fbmGreen(x*0.028,z*0.028)*0.13;
        h=lerp(h,greenH,1-sstep(1.0,2.8,gv));
      }

      // Bunker bowls
      for (const b of p.bunkers) {
        const bv=ellipseVal(b.bx,b.bz,b.rx,b.rz,x,z);
        if (bv<2.2) {
          const t=Math.max(0,1-bv);
          h-=b.depth*Math.pow(t,1.25);
          h+=0.13*Math.exp(-((bv-1.18)**2)/0.03);
        }
      }
    }

    // Water carving
    for (const w of waters) {
      const wv=ellipseVal(w.cx,w.cz,w.rx,w.rz,x,z);
      if (wv<1.35) h=lerp(h,w.level-0.6,sstep(1.35,0.75,wv)*0.95);
    }

    return h;
  }

  return { heightAt, fbmDetail };
}

// ---------- Branch-card tree kit ----------
const PINE_SPRIG  = {u0:0.030,v0:0.550,u1:0.225,v1:0.985};
const LEAF_RECT_A = {u0:0.010,v0:0.270,u1:0.440,v1:0.740};
const LEAF_RECT_B = {u0:0.040,v0:0.005,u1:0.420,v1:0.460};

function cardGeo(w,h,rect) {
  const g=new THREE.PlaneGeometry(w,h); g.translate(0,h/2,0);
  const uv=g.attributes.uv;
  for(let i=0;i<uv.count;i++) uv.setXY(i,rect.u0+uv.getX(i)*(rect.u1-rect.u0),rect.v0+uv.getY(i)*(rect.v1-rect.v0));
  return g;
}
const _m4=new THREE.Matrix4(),_q=new THREE.Quaternion(),_eu=new THREE.Euler();
function placed(geo,px,py,pz,rx,ry,rz,s=1) {
  const g=geo.clone(); _eu.set(rx,ry,rz,'YXZ'); _q.setFromEuler(_eu);
  _m4.compose(new THREE.Vector3(px,py,pz),_q,new THREE.Vector3(s,s,s)); g.applyMatrix4(_m4); return g;
}
function normalsUp(geo){const n=geo.attributes.normal;for(let i=0;i<n.count;i++)n.setXYZ(i,0,1,0);return geo;}
function pineCanopy(seed) {
  const rng=makeRng(seed),sprig=cardGeo(1.9,3.2,PINE_SPRIG),cards=[];
  for(let y=2.4;y<=8.2;y+=0.92){const t=(y-2.4)/5.8,n=Math.round(6-3*t),s=1.15-0.62*t;
    for(let i=0;i<n;i++){const yaw=(i/n)*Math.PI*2+rng()*1.2,pitch=-(Math.PI/2)+0.38+rng()*0.25;
      cards.push(placed(sprig,0,y+(rng()-0.5)*0.3,0,pitch,yaw,0,s*(0.85+rng()*0.3)));}}
  cards.push(placed(sprig,0,8.0,0,-0.06,rng()*Math.PI,0,0.8));
  cards.push(placed(sprig,0,8.0,0,-0.06,rng()*Math.PI+Math.PI/2,0,0.72));
  return normalsUp(mergeGeometries(cards));
}
function leafCanopy(seed) {
  const rng=makeRng(seed),a=cardGeo(3.1,3.1,LEAF_RECT_A),b=cardGeo(2.8,3.0,LEAF_RECT_B),cards=[];
  for(let i=0;i<26;i++){const az=rng()*Math.PI*2,elev=(rng()-0.32)*1.9,r=0.7+rng()*1.9;
    const px=Math.cos(az)*Math.cos(elev)*r,pz=Math.sin(az)*Math.cos(elev)*r,py=5.2+Math.sin(elev)*r*0.8;
    cards.push(placed(rng()<0.5?a:b,px,py-1.4,pz,(rng()-0.6)*1.1,rng()*Math.PI*2,(rng()-0.5)*0.7,0.8+rng()*0.5));}
  return normalsUp(mergeGeometries(cards));
}
function trunkGeo(rTop,rBot,h,vRepeat) {
  const g=new THREE.CylinderGeometry(rTop,rBot,h,8,1,true); g.translate(0,h/2,0);
  const uv=g.attributes.uv; for(let i=0;i<uv.count;i++) uv.setY(i,uv.getY(i)*vRepeat); return g;
}

const _canopyMats=[];
export function setTreeFade(camX,camZ,treePositions) {
  if(!_canopyMats.length||!treePositions?.length) return;
  let minD=Infinity;
  for(const t of treePositions){const d=Math.hypot(camX-t.x,camZ-t.z);if(d<minD)minD=d;}
  const fade=Math.max(0.06,Math.min(1,(minD-3)/11)), near=fade<1;
  for(const mat of _canopyMats){
    mat.transparent=near;mat.depthWrite=!near;mat.opacity=fade;
    if(near)mat.alphaTest=0;else mat.alphaTest=mat._cut;
  }
}

let _treeKit=null;
function getTreeKit(assets) {
  if(_treeKit) return _treeKit;
  const t=assets.trees, swayShaders=[];
  const addSway=(mat)=>{
    mat.onBeforeCompile=(shader)=>{
      shader.uniforms.uTime={value:0};shader.uniforms.uWind={value:1};swayShaders.push(shader);
      shader.vertexShader=shader.vertexShader
        .replace('#include <common>',`#include <common>\nuniform float uTime;uniform float uWind;`)
        .replace('#include <begin_vertex>',`#include <begin_vertex>
          {
            #ifdef USE_INSTANCING
              float ph=instanceMatrix[3].x*0.73+instanceMatrix[3].z*1.11;
            #else
              float ph=0.0;
            #endif
            float reach=max(transformed.y-1.5,0.0);
            float sway=sin(uTime*(0.9+0.25*sin(ph))+ph)*(0.006+0.004*uWind)*reach;
            transformed.x+=sway;transformed.z+=sway*0.6;
            transformed.y+=sin(uTime*1.7+ph*1.3)*0.008*reach;
          }`);
    }; return mat;
  };
  const canopyMat=(map,cut)=>{const m=addSway(new THREE.MeshLambertMaterial({map,alphaTest:cut,side:THREE.DoubleSide}));m._cut=cut;_canopyMats.push(m);return m;};
  const depthMat=(map,cut)=>new THREE.MeshDepthMaterial({depthPacking:THREE.RGBADepthPacking,map,alphaTest:cut});
  _treeKit={
    canopies:[
      {geo:pineCanopy(11),mat:canopyMat(t.pineCard,0.52),depth:depthMat(t.pineCard,0.52),trunk:'pine'},
      {geo:pineCanopy(47),mat:canopyMat(t.pineCard,0.52),depth:depthMat(t.pineCard,0.52),trunk:'pine'},
      {geo:leafCanopy(23),mat:canopyMat(t.leafCard,0.4), depth:depthMat(t.leafCard,0.4), trunk:'leaf'},
      {geo:leafCanopy(89),mat:canopyMat(t.leafCard,0.4), depth:depthMat(t.leafCard,0.4), trunk:'leaf'},
    ],
    trunks:{
      pine:{geo:trunkGeo(0.07,0.30,8.6,3),mat:new THREE.MeshLambertMaterial({map:t.pineBark})},
      leaf:{geo:trunkGeo(0.14,0.36,4.8,2),mat:new THREE.MeshLambertMaterial({map:t.leafBark})},
    },
    swayShaders,
  };
  return _treeKit;
}

// ---------- Terrain mesh — satellite overlay + boundary clip ----------
// Satellite image is used directly as the map texture on a MeshBasicMaterial
// so it shows at full aerial-photo brightness regardless of lighting angle.
// UV coordinates are baked per-vertex from world XZ → satellite image space.
// Vertices outside the OSM boundary polygon are pushed underground so the
// course "stops" at the real property edge.
function buildTerrainMesh(courseData, heightAt, assets) {
  const {minX,maxX,minZ,maxZ}=courseData.bbox;
  const boundary=courseData.boundary||[];

  // Satellite UV bounds
  const OLAT=40.793526,OLNG=-74.38804,COS_LAT=0.757;
  const sb=assets.satBounds||{minLat:40.7868,maxLat:40.8055,minLng:-74.3994,maxLng:-74.3774};
  const satMinX=(sb.minLng-OLNG)*COS_LAT*111320;
  const satMaxX=(sb.maxLng-OLNG)*COS_LAT*111320;
  const satMinZ=(sb.minLat-OLAT)*111320;
  const satMaxZ=(sb.maxLat-OLAT)*111320;
  const satRangeX=satMaxX-satMinX, satRangeZ=satMaxZ-satMinZ;

  const SEG=5;
  const cols=Math.floor((maxX-minX)/SEG)+1;
  const rows=Math.floor((maxZ-minZ)/SEG)+1;

  const positions=new Float32Array(cols*rows*3);
  const uvs      =new Float32Array(cols*rows*2);
  const indices  =[];

  for(let r=0;r<rows;r++) for(let c=0;c<cols;c++) {
    const idx=r*cols+c;
    const x=minX+c*SEG, z=minZ+r*SEG;
    // Push vertices outside the OSM boundary underground
    const inBounds=boundary.length<3||pip(x,z,boundary);
    const y=inBounds?heightAt(x,z):-10;
    positions[idx*3]=x; positions[idx*3+1]=y; positions[idx*3+2]=z;
    uvs[idx*2]  =Math.max(0.001,Math.min(0.999,(x-satMinX)/satRangeX));
    uvs[idx*2+1]=Math.max(0.001,Math.min(0.999,(z-satMinZ)/satRangeZ));
  }

  for(let r=0;r<rows-1;r++) for(let c=0;c<cols-1;c++) {
    const a=r*cols+c,b=a+1,d=(r+1)*cols+c,e=d+1;
    // Skip quads that are entirely underground (outside boundary)
    const allUnder=[a,b,d,e].every(i=>positions[i*3+1]<-5);
    if(!allUnder) indices.push(a,d,b,b,d,e);
  }

  const geo=new THREE.BufferGeometry();
  geo.setAttribute('position',new THREE.BufferAttribute(positions,3));
  geo.setAttribute('uv',      new THREE.BufferAttribute(uvs,2));
  geo.setIndex(indices);
  geo.computeVertexNormals();

  const mesh=new THREE.Mesh(geo,new THREE.MeshBasicMaterial({map:assets.satellite}));
  mesh.receiveShadow=false; mesh.name='terrain';
  return mesh;
}

// ---------- Dense tree line along OSM boundary ----------
function buildBoundaryTrees(boundary, heightAt, scene, assets) {
  if(!boundary||boundary.length<3) return;
  const kit=getTreeKit(assets);
  const rng=makeRng(4242);
  const spots=[];

  for(let i=0;i<boundary.length;i++) {
    const [ax,az]=boundary[i],[bx,bz]=boundary[(i+1)%boundary.length];
    const segLen=Math.hypot(bx-ax,bz-az);
    const steps=Math.ceil(segLen/7);
    for(let s=0;s<steps;s++) {
      const t=s/steps;
      // Offset slightly inward (+random) so trees straddle the boundary line
      const nx=-(bz-az)/segLen, nz=(bx-ax)/segLen; // inward normal
      const jx=(rng()-0.5)*4, jz=(rng()-0.5)*4;
      const x=ax+(bx-ax)*t+nx*3+jx;
      const z=az+(bz-az)*t+nz*3+jz;
      spots.push({
        x, z, h: heightAt(x,z),
        s: 0.55+rng()*0.9,
        ry: rng()*Math.PI*2,
        tilt: (rng()-0.5)*0.06,
        kind: rng()<0.5?0:2,
        tint:[0.72+rng()*0.2, 0.85+rng()*0.15, 0.68+rng()*0.2],
      });
    }
  }

  const m4=new THREE.Matrix4(),q=new THREE.Quaternion(),eu=new THREE.Euler();
  const v3=new THREE.Vector3(),s3=new THREE.Vector3(),col=new THREE.Color();
  function setInst(im,mine,tinted) {
    mine.forEach((t,i)=>{
      eu.set(t.tilt,t.ry,t.tilt*0.7);q.setFromEuler(eu);
      v3.set(t.x,t.h-0.12,t.z);s3.set(t.s,t.s,t.s);m4.compose(v3,q,s3);im.setMatrixAt(i,m4);
      if(tinted){col.setRGB(t.tint[0],t.tint[1],t.tint[2]);im.setColorAt(i,col);}
    });
    im.instanceMatrix.needsUpdate=true;if(im.instanceColor)im.instanceColor.needsUpdate=true;scene.add(im);
  }
  for(let k=0;k<kit.canopies.length;k++){
    const mine=spots.filter(t=>t.kind===k);if(!mine.length)continue;
    const c=kit.canopies[k];
    const im=new THREE.InstancedMesh(c.geo,c.mat,mine.length);
    im.customDepthMaterial=c.depth;im.castShadow=true;setInst(im,mine,true);
  }
  for(const species of ['pine','leaf']){
    const mine=spots.filter(t=>kit.canopies[t.kind].trunk===species);if(!mine.length)continue;
    const tk=kit.trunks[species];
    const im=new THREE.InstancedMesh(tk.geo,tk.mat,mine.length);im.castShadow=true;setInst(im,mine,false);
  }
}

// ---------- Water ----------
function buildWater(courseData, heightAt, scene, assets) {
  const waters=[];
  const allPolys=[...(courseData.globalWater||[]),...courseData.holes.flatMap(h=>h.water||[])];
  for(const poly of allPolys) {
    if(!poly||poly.length<3) continue;
    const xs=poly.map(p=>p[0]),zs=poly.map(p=>p[1]);
    const cx=(Math.min(...xs)+Math.max(...xs))/2, cz=(Math.min(...zs)+Math.max(...zs))/2;
    const sx=Math.max(...xs)-Math.min(...xs)+20, sz=Math.max(...zs)-Math.min(...zs)+20;
    const y=Math.min(...poly.map(p=>heightAt(p[0],p[1])))-0.3;
    const water=new Water(new THREE.PlaneGeometry(sx,sz),{
      textureWidth:512,textureHeight:512,
      waterNormals:assets.waterN,
      sunDirection:assets.sunDir.clone(),
      sunColor:0xffffff,waterColor:0x0d4f6e,
      distortionScale:1.8,fog:true,
    });
    water.rotation.x=-Math.PI/2; water.position.set(cx,y,cz);
    scene.add(water); waters.push(water);
  }
  return waters;
}

// ---------- Trees from real course positions ----------
function buildTrees(courseData, heightAt, scene, assets) {
  if(!courseData.trees?.length) return {swayShaders:[],spots:[]};
  const kit=getTreeKit(assets);
  const m4=new THREE.Matrix4(),q=new THREE.Quaternion(),eu=new THREE.Euler();
  const v3=new THREE.Vector3(),s3=new THREE.Vector3(),col=new THREE.Color();
  const spots=courseData.trees.map((t,i)=>({
    x:t.x,z:t.z,h:heightAt(t.x,t.z),
    s:(t.r/3.2)*(0.65+(i%97)/97*0.7),
    ry:(i*2.39996)%(Math.PI*2),
    tilt:((i%13)/13-0.5)*0.07,
    kind:t.isPine?(i%2):2+(i%2),
    tint:[0.82+(i%17)/17*0.34,0.84+(i%23)/23*0.34,0.82+(i%11)/11*0.28],
  }));
  function setInstances(im,mine,tinted) {
    mine.forEach((t,i)=>{
      eu.set(t.tilt,t.ry,t.tilt*0.7);q.setFromEuler(eu);
      v3.set(t.x,t.h-0.12,t.z);s3.set(t.s,t.s,t.s);m4.compose(v3,q,s3);im.setMatrixAt(i,m4);
      if(tinted){col.setRGB(t.tint[0],t.tint[1],t.tint[2]);im.setColorAt(i,col);}
    });
    im.instanceMatrix.needsUpdate=true;if(im.instanceColor)im.instanceColor.needsUpdate=true;scene.add(im);
  }
  for(let k=0;k<kit.canopies.length;k++){
    const mine=spots.filter(t=>t.kind===k);if(!mine.length)continue;
    const c=kit.canopies[k];
    const im=new THREE.InstancedMesh(c.geo,c.mat,mine.length);
    im.customDepthMaterial=c.depth;im.castShadow=true;setInstances(im,mine,true);
  }
  for(const species of ['pine','leaf']){
    const mine=spots.filter(t=>kit.canopies[t.kind].trunk===species);if(!mine.length)continue;
    const tk=kit.trunks[species];
    const im=new THREE.InstancedMesh(tk.geo,tk.mat,mine.length);im.castShadow=true;setInstances(im,mine,false);
  }
  return {swayShaders:kit.swayShaders,spots};
}

// ---------- Backdrop treeline ----------
function buildBackdrop(bbox,scene) {
  const {minX,maxX,minZ,maxZ}=bbox;
  const ccx=(minX+maxX)/2,ccz=(minZ+maxZ)/2,radius=Math.max(maxX-ccx,maxZ-ccz)+200;
  const fbmBack=makeFbm(77,3);
  const rgeo=new THREE.CylinderGeometry(radius,radius,1,140,1,true);
  const rpos=rgeo.attributes.position,rcol=new Float32Array(rpos.count*3);
  const lo=new THREE.Color(0x2f4d28),hi=new THREE.Color(0x5d7a55).lerp(new THREE.Color(0xaebfd0),0.45);
  for(let i=0;i<rpos.count;i++){
    const x=rpos.getX(i),z=rpos.getZ(i),top=rpos.getY(i)>0;
    const a=Math.atan2(z,x),n=fbmBack(Math.cos(a)*2.4+4,Math.sin(a)*2.4)*0.5+0.5;
    rpos.setY(i,top?10+n*9:-6);
    const c=top?hi:lo;rcol[i*3]=c.r;rcol[i*3+1]=c.g;rcol[i*3+2]=c.b;
  }
  rgeo.setAttribute('color',new THREE.BufferAttribute(rcol,3));
  const rm=new THREE.Mesh(rgeo,new THREE.MeshBasicMaterial({vertexColors:true,side:THREE.BackSide,fog:true}));
  rm.position.set(ccx,0,ccz);scene.add(rm);
}

// ---------- Flags + cups ----------
function buildHoleMarkers(courseData,heightAt,scene) {
  for(const hole of courseData.holes){
    const[gx,gz]=hole.green.center,y=heightAt(gx,gz);
    const pole=new THREE.Mesh(new THREE.CylinderGeometry(0.022,0.022,2.25,8),
      new THREE.MeshLambertMaterial({color:0xf4f1e6}));
    pole.position.set(gx,y+1.125,gz);pole.castShadow=true;
    const flagGeo=new THREE.PlaneGeometry(0.62,0.4);flagGeo.translate(0.31,0,0);
    const flag=new THREE.Mesh(flagGeo,new THREE.MeshLambertMaterial({color:0xc23a28,side:THREE.DoubleSide}));
    flag.position.set(gx,y+2.0,gz);
    const cup=new THREE.Mesh(new THREE.CircleGeometry(0.075,20),new THREE.MeshBasicMaterial({color:0x10160f}));
    cup.rotation.x=-Math.PI/2;cup.position.set(gx,y+0.012,gz);
    scene.add(pole,flag,cup);
  }
}

// ---------- Module singletons ----------
let _heightAt,_surfaceAt,_waterRef,_terrainShader,_swayShaders;

// ---------- Main export ----------
export function buildWorld(courseData,scene,assets) {
  _treeKit=null; _canopyMats.length=0;

  const {minX,maxX,minZ,maxZ}=courseData.bbox;
  const width=maxX-minX, depth=maxZ-minZ;

  // Surface map: pip() against real OSM polygons (gives correct course layout)
  const sm=buildSurfaceMap(courseData,minX,minZ,width,depth);
  _surfaceAt=sm.surfaceAt;

  // Height field: analytic FBM (smooth terrain, no API needed)
  const hf=buildHeightField(courseData);
  _heightAt=hf.heightAt;

  const terrain=buildTerrainMesh(courseData,hf.heightAt,assets);
  scene.add(terrain);
  _terrainShader=terrain.material.userData;

  buildBackdrop(courseData.bbox,scene);
  buildHoleMarkers(courseData,hf.heightAt,scene);

  const waters=buildWater(courseData,hf.heightAt,scene,assets);
  _waterRef=waters;

  const treeResult=buildTrees(courseData,hf.heightAt,scene,assets);
  buildBoundaryTrees(courseData.boundary,hf.heightAt,scene,assets);
  _swayShaders=treeResult.swayShaders;

  return {terrain,waterPlanes:waters};
}

export function updateWorld(t,windVec) {
  if(_waterRef) for(const w of _waterRef) w.material.uniforms.time.value=t*0.5;
  if(_terrainShader?.shader?.uniforms?.uTime!==undefined){
    _terrainShader.shader.uniforms.uTime.value=t;
    if(windVec)_terrainShader.shader.uniforms.uWindVec?.value?.set(windVec.x,windVec.z);
  }
  if(_swayShaders) for(const sh of _swayShaders){
    sh.uniforms.uTime.value=t;
    if(windVec)sh.uniforms.uWind.value=Math.hypot(windVec.x,windVec.z);
  }
}

export function heightAt(x,z) {return _heightAt?_heightAt(x,z):0;}
export function surfaceAt(x,z){return _surfaceAt?_surfaceAt(x,z):SURF.ROUGH;}
export function slopeAt(x,z) {
  const eps=0.5,h0=heightAt(x,z),hpx=heightAt(x+eps,z)-h0,hpz=heightAt(x,z+eps)-h0;
  const len=Math.hypot(-hpx,eps,-hpz)||1;
  return{nx:-hpx/len,ny:eps/len,nz:-hpz/len};
}

export function holeCameraPos(hole) {
  const[tx,tz]=hole.tee,[gx,gz]=hole.green.center;
  const dx=gx-tx,dz=gz-tz,len=Math.hypot(dx,dz)||1;
  return{cx:tx+(dx/len)*2,cy:heightAt(tx,tz)+1.7,cz:tz+(dz/len)*2,tx:gx,ty:heightAt(gx,gz)+0.5,tz:gz};
}

export function drawMinimapBase(courseData,canvas,holeIdx=null) {
  const ctx=canvas.getContext('2d'),W=canvas.width,H=canvas.height;
  let minX,maxX,minZ,maxZ;
  const activeHole=holeIdx!==null?courseData.holes[holeIdx]:null;
  if(activeHole){
    const pts=[activeHole.tee,activeHole.green.center,...(activeHole.fairway||[]),...(activeHole.green.polygon||[]),...activeHole.bunkers.flat(),...activeHole.water.flat()];
    const xs=pts.map(p=>p[0]),zs=pts.map(p=>p[1]),pad=35;
    minX=Math.min(...xs)-pad;maxX=Math.max(...xs)+pad;minZ=Math.min(...zs)-pad;maxZ=Math.max(...zs)+pad;
    const span=Math.max(maxX-minX,maxZ-minZ),cx=(minX+maxX)/2,cz=(minZ+maxZ)/2;
    minX=cx-span/2;maxX=cx+span/2;minZ=cz-span/2;maxZ=cz+span/2;
  } else {
    const b=courseData.bbox;minX=b.minX;maxX=b.maxX;minZ=b.minZ;maxZ=b.maxZ;
  }
  const scaleX=W/(maxX-minX),scaleZ=H/(maxZ-minZ);
  function toC(x,z){return[(x-minX)*scaleX,(z-minZ)*scaleZ];}
  ctx.clearRect(0,0,W,H);ctx.fillStyle='#1e3a10';ctx.fillRect(0,0,W,H);
  function drawPoly(poly,color,alpha=1){
    if(!poly?.length)return;
    ctx.save();ctx.globalAlpha=alpha;ctx.beginPath();ctx.fillStyle=color;
    const[px,pz]=toC(poly[0][0],poly[0][1]);ctx.moveTo(px,pz);
    for(let i=1;i<poly.length;i++){const[qx,qz]=toC(poly[i][0],poly[i][1]);ctx.lineTo(qx,qz);}
    ctx.closePath();ctx.fill();ctx.restore();
  }
  if(activeHole) for(const hole of courseData.holes){if(hole===activeHole)continue;drawPoly(hole.fairway,'#2a4e12',0.35);}
  for(const w of(courseData.globalWater||[]))drawPoly(w,'#2060a8');
  const holesToDraw=activeHole?[activeHole]:courseData.holes;
  for(const hole of holesToDraw){
    drawPoly(hole.fairway,'#3a6a18');
    for(const b of hole.bunkers)drawPoly(b,'#c8a84a');
    for(const w of(hole.water||[]))drawPoly(w,'#2060a8');
    if(hole.green.polygon)drawPoly(hole.green.polygon,'#50cc60');
  }
  const pathScale=Math.min(scaleX,scaleZ);
  for(const path of(courseData.cartPaths||[])){
    if(path.length<2)continue;
    const visible=path.filter(([x,z])=>x>=minX&&x<=maxX&&z>=minZ&&z<=maxZ);
    if(visible.length<2)continue;
    ctx.beginPath();ctx.strokeStyle='rgba(180,175,155,0.75)';ctx.lineWidth=Math.max(1,pathScale*3.5);
    const[px,pz]=toC(path[0][0],path[0][1]);ctx.moveTo(px,pz);
    for(let i=1;i<path.length;i++){const[qx,qz]=toC(path[i][0],path[i][1]);ctx.lineTo(qx,qz);}
    ctx.stroke();
  }
  for(const hole of holesToDraw){
    if(hole.path?.length>1){
      ctx.strokeStyle='rgba(255,255,255,0.3)';ctx.lineWidth=0.8;ctx.beginPath();
      const[px,pz]=toC(hole.path[0][0],hole.path[0][1]);ctx.moveTo(px,pz);
      for(let i=1;i<hole.path.length;i++){const[qx,qz]=toC(hole.path[i][0],hole.path[i][1]);ctx.lineTo(qx,qz);}
      ctx.stroke();
    }
  }
  for(const hole of holesToDraw){
    const[tx,tz]=toC(hole.tee[0],hole.tee[1]);
    ctx.fillStyle='#ffffff';ctx.beginPath();ctx.arc(tx,tz,activeHole?4:2.5,0,Math.PI*2);ctx.fill();
    if(activeHole){ctx.fillStyle='#fff';ctx.font='bold 10px system-ui';ctx.textAlign='center';ctx.fillText('H'+hole.number,tx,tz-7);}
  }
  for(const hole of holesToDraw){
    const[px,pz]=toC(hole.green.center[0],hole.green.center[1]);
    ctx.fillStyle='#ffd700';ctx.beginPath();ctx.arc(px,pz,activeHole?5:3,0,Math.PI*2);ctx.fill();
  }
  return{toC,scaleX,scaleZ};
}
