const THREE = (() => {
  class Vector3 {
    constructor(x=0,y=0,z=0){this.x=x;this.y=y;this.z=z;}
    normalize(){const l=Math.hypot(this.x,this.y,this.z)||1;this.x/=l;this.y/=l;this.z/=l;return this;}
    set(x,y,z){this.x=x;this.y=y;this.z=z;return this;}
    copy(v){this.x=v.x;this.y=v.y;this.z=v.z;return this;}
    multiplyScalar(s){this.x*=s;this.y*=s;this.z*=s;return this;}
    lerp(v,t){this.x+=(v.x-this.x)*t;this.y+=(v.y-this.y)*t;this.z+=(v.z-this.z)*t;return this;}
    clone(){return new Vector3(this.x,this.y,this.z);}
  }
  class Color {
    constructor(){this.r=1;this.g=1;this.b=1;}
    copy(c){this.r=c.r;this.g=c.g;this.b=c.b;return this;}
    lerp(c,t){this.r+=(c.r-this.r)*t;this.g+=(c.g-this.g)*t;this.b+=(c.b-this.b)*t;return this;}
    multiplyScalar(s){this.r*=s;this.g*=s;this.b*=s;return this;}
  }
  class Geo {
    constructor(){this.attributes={position:{array:new Float32Array(120),needsUpdate:false}};}
    setAttribute(n,a){this.attributes[n]=a;return this;}
    setIndex(){} computeVertexNormals(){} translate(){return this;}
    dispose(){} setFromPoints(){return this;} setDrawRange(){}
  }
  class BufferAttribute{constructor(arr,sz){this.array=arr;this.itemSize=sz;}}
  class Obj3D {
    constructor(){this.position=new Vector3();this.rotation={x:0,y:0,z:0};this.scale=new Vector3(1,1,1);this.children=[];}
    add(o){this.children.push(o);return this;}
    traverse(fn){fn(this);this.children.forEach(c=>c.traverse?c.traverse(fn):fn(c));}
  }
  class Mesh extends Obj3D{constructor(g,m){super();this.geometry=g;this.material=m;}}
  class InstancedMesh extends Mesh{constructor(g,m,n){super(g,m);this.instanceMatrix={needsUpdate:false};}setMatrixAt(){}}
  class Mat{dispose(){}}
  class Matrix4{compose(){return this;}}
  class Quaternion{setFromEuler(){return this;}}
  class Euler{set(){return this;}}
  return {Vector3,Color,BufferGeometry:Geo,PlaneGeometry:Geo,CylinderGeometry:Geo,ConeGeometry:Geo,
    IcosahedronGeometry:Geo,SphereGeometry:Geo,CircleGeometry:Geo,TorusGeometry:Geo,BufferAttribute,
    Group:Obj3D,Mesh,InstancedMesh,MeshLambertMaterial:Mat,MeshPhongMaterial:Mat,MeshBasicMaterial:Mat,
    DoubleSide:2,Matrix4,Quaternion,Euler};
})();
// extras referenced by the /play sim's terrain at module scope or in stubs
THREE.Vector2 = class { constructor(x=0,y=0){this.x=x;this.y=y;} };
THREE.MeshStandardMaterial = class { constructor(){this.userData={};} dispose(){} };
