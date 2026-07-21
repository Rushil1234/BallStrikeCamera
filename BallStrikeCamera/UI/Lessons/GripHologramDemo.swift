import SwiftUI
import SceneKit
import simd

// MARK: - GripHologramDemo
//
// A real 3D SceneKit grip demo built from ACTUAL MediaPipe hand landmarks (see
// GripReferencePose). Each hand is reconstructed from its 21 tracked joints — spheres at
// the joints, tapered capsules along the bones — so it reads as a true human hand, not a
// placeholder. The two hands start apart, float together, and settle into the captured
// grip around a 3D club. Holographic translucent look; drag to orbit.

struct GripHologramDemo: View {
    var body: some View {
        GripHologramSceneView()
            .background(
                RadialGradient(colors: [Color(red: 0.07, green: 0.16, blue: 0.16),
                                        Color(red: 0.02, green: 0.05, blue: 0.05)],
                               center: .center, startRadius: 20, endRadius: 340)
            )
    }
}

private struct GripHologramSceneView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.scene = Self.buildScene()
        v.pointOfView = v.scene?.rootNode.childNode(withName: "camera", recursively: true)
        v.rendersContinuously = true
        v.allowsCameraControl = true
        return v
    }
    func updateUIView(_ v: SCNView, context: Context) {}

    // MARK: Scene

    private static func buildScene() -> SCNScene {
        let scene = SCNScene()
        let root = scene.rootNode

        // Center + scale the captured grip so it sits nicely at the origin.
        let all = GripReferencePose.grip.flatMap { $0 }
        let center = all.reduce(SIMD3<Float>(0, 0, 0), +) / Float(all.count)
        let sceneScale: Float = 9.0
        func toScene(_ p: SIMD3<Float>) -> SCNVector3 {
            SCNVector3((p.x - center.x) * sceneScale,
                       -(p.y - center.y) * sceneScale,      // image y is down; scene y is up
                       -(p.z - center.z) * sceneScale)      // depth toward camera
        }

        // Camera — slight 3/4 angle for a 3D read.
        let cam = SCNNode(); cam.name = "camera"; cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 45
        cam.position = SCNVector3(1.2, 0.8, 8.5)
        cam.look(at: SCNVector3(0, 0, 0))
        root.addChildNode(cam)

        // Holographic lighting.
        let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient
        amb.light?.color = UIColor(red: 0.55, green: 0.85, blue: 0.9, alpha: 1)
        amb.light?.intensity = 850
        root.addChildNode(amb)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional
        key.light?.intensity = 450; key.eulerAngles = SCNVector3(-0.7, 0.6, 0)
        root.addChildNode(key)

        // ── Club through the grip ──────────────────────────────────────
        let shaft = SCNCylinder(radius: 0.34, height: 13)
        let sm = SCNMaterial(); sm.diffuse.contents = UIColor(white: 0.09, alpha: 1)
        sm.roughness.contents = 0.5; shaft.materials = [sm]
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.eulerAngles = SCNVector3(0, 0, -0.18)   // slight lie angle
        shaftNode.position = SCNVector3(0, 0, -1.0)        // behind the hands
        root.addChildNode(shaftNode)
        let grip = SCNCylinder(radius: 0.4, height: 5)
        let gm = SCNMaterial(); gm.diffuse.contents = UIColor(white: 0.15, alpha: 1)
        grip.materials = [gm]
        let gripNode = SCNNode(geometry: grip); gripNode.position = SCNVector3(0, 2, 0)
        shaftNode.addChildNode(gripNode)

        _ = toScene   // (raw scene mapping kept for reference; hands use canonical frames)

        // ── RIGGED HAND MESH (preferred, VR-realistic) ─────────────────
        // Drop a rigged/skinned hand model named "HandModel.usdz" (or .scn) into the app
        // bundle and it's used automatically — two instances (trail mirrored) posed on the
        // grip with the holographic material. Falls back to the landmark-built hands below
        // when no asset is present, so the demo always renders.
        if let handURL = Bundle.main.url(forResource: "HandModel", withExtension: "usdz")
            ?? Bundle.main.url(forResource: "HandModel", withExtension: "scn"),
           let loaded = try? SCNScene(url: handURL, options: [.checkConsistency: false]),
           let handMesh = loaded.rootNode.childNodes.first {
            applyHologramMaterial(handMesh)
            let leadGrip = SCNVector3(0, 1.4, 0.3)
            let trailGrip = SCNVector3(0, -1.2, 0.3)
            for (hi, target) in [leadGrip, trailGrip].enumerated() {
                guard let hand = handMesh.clone() as SCNNode? else { continue }
                // Fit the model to the grip: normalize to ~3 units tall.
                let (minB, maxB) = hand.boundingBox
                let h = max(maxB.y - minB.y, 0.001)
                let s = 3.0 / h
                hand.scale = SCNVector3(hi == 0 ? s : -s, s, s)   // mirror the trail hand
                hand.eulerAngles = SCNVector3(0, Float.pi * 0.5, 0)
                root.addChildNode(hand)
                let start = SCNVector3(-7.5, target.y - 3, 3.5)
                hand.position = start; hand.opacity = 0
                let under = SCNVector3(-1.5, target.y - 2, 1.6)
                hand.runAction(.repeatForever(.sequence([
                    .wait(duration: 0.2 + Double(hi) * 1.0),
                    .fadeIn(duration: 0.4),
                    { let a = SCNAction.move(to: under, duration: 0.7); a.timingMode = .easeIn; return a }(),
                    { let a = SCNAction.move(to: target, duration: 0.7); a.timingMode = .easeOut; return a }(),
                    .wait(duration: 2.0), .fadeOut(duration: 0.5),
                    .run { $0.position = start }, .wait(duration: 0.4)])))
            }
            return scene
        }

        // ── Two real hands, CANONICALIZED so we control orientation ─────
        // The captured world orientation is arbitrary; re-express each hand in its own
        // frame (wrist at origin, fingers +Y, palm +Z) so we can place it as a real grip:
        // lead hand comes from the LEFT and wraps UNDER the club, trail stacks below it.
        let colors = [UIColor(red: 0.32, green: 0.98, blue: 0.82, alpha: 1),  // lead (left hand)
                      UIColor(red: 0.30, green: 0.92, blue: 1.0, alpha: 1)]   // trail
        // Pick the two hands; put the LEFT-handed one first as the lead (top) hand.
        let ordered = GripReferencePose.grip.sorted { ($0.first?.x ?? 0) < ($1.first?.x ?? 0) }

        for (hi, hand) in ordered.enumerated() {
            let local = canonicalHand(hand, scale: 12.0)     // bigger; wrist-origin, fingers +Y
            let handNode = buildHand(local: local, color: colors[hi % 2])

            // Grip orientation: rotate so the fingers wrap toward the club and the hand
            // sits under the grip. Lead (hi==0) on top, trail (hi==1) just below.
            let onGrip = SCNVector3(0, hi == 0 ? 1.5 : -1.3, 0.2)
            // Fingers point toward the club (+X) and curl over the top; palm faces the shaft.
            handNode.eulerAngles = SCNVector3(Float.pi * 0.08, Float.pi * 0.5, Float.pi * (hi == 0 ? 0.5 : 0.55))
            root.addChildNode(handNode)

            // Come in from the LEFT and sweep UNDER the club up to the grip.
            let start = SCNVector3(-7.5, onGrip.y - 3.0, 3.5)
            handNode.position = start
            handNode.opacity = 0
            let appear = SCNAction.fadeIn(duration: 0.4)
            // Two-leg path: in from the left, then up-and-under to the grip.
            let under = SCNVector3(-1.5, onGrip.y - 2.2, 1.6)
            let leg1 = SCNAction.move(to: under, duration: 0.7); leg1.timingMode = .easeIn
            let leg2 = SCNAction.move(to: onGrip, duration: 0.7); leg2.timingMode = .easeOut
            let hold = SCNAction.wait(duration: 2.0)
            let fade = SCNAction.fadeOut(duration: 0.5)
            let reset = SCNAction.run { node in node.position = start }
            handNode.runAction(.repeatForever(.sequence([
                .wait(duration: 0.2 + Double(hi) * 1.0), appear, leg1, leg2, hold, fade, reset,
                .wait(duration: 0.4)])))
        }
        return scene
    }

    /// Holographic translucent cyan look applied to every material of a loaded hand mesh.
    private static func applyHologramMaterial(_ node: SCNNode) {
        let cyan = UIColor(red: 0.32, green: 0.95, blue: 1.0, alpha: 1)
        node.enumerateHierarchy { n, _ in
            guard let g = n.geometry else { return }
            let m = SCNMaterial()
            m.diffuse.contents = cyan.withAlphaComponent(0.30)
            m.emission.contents = cyan.withAlphaComponent(0.75)
            m.transparency = 0.7
            m.transparencyMode = .dualLayer
            m.lightingModel = .constant
            m.isDoubleSided = true
            g.materials = [m]
        }
    }

    /// Re-express a hand's 21 landmarks in its OWN frame: wrist at origin, fingers along
    /// +Y (wrist→middle-MCP), palm normal +Z, thumb side +X. Returns scaled local points so
    /// the scene can orient/place the hand however it likes (the captured world pose's
    /// arbitrary orientation is discarded — only the true hand SHAPE is kept).
    private static func canonicalHand(_ pts: [SIMD3<Float>], scale: Float) -> [SCNVector3] {
        let w = pts[0]
        let yA = simd_normalize(pts[9] - w)                 // wrist → middle MCP
        let ref = simd_normalize(pts[5] - w)                // wrist → index MCP
        var zA = simd_cross(ref, yA)                        // palm normal
        if simd_length(zA) < 1e-4 { zA = SIMD3<Float>(0, 0, 1) }
        zA = simd_normalize(zA)
        let xA = simd_normalize(simd_cross(yA, zA))
        var local = pts.map { p -> SIMD3<Float> in
            let d = p - w
            return SIMD3<Float>(simd_dot(d, xA) * scale, simd_dot(d, yA) * scale, simd_dot(d, zA) * scale)
        }
        // The source clip's fingers are splayed/open, not gripping. Procedurally CURL each
        // finger around the club: walk MCP→tip, bending each joint toward the palm (+Z) by
        // a growing angle so the fingertips wrap. Thumb curls less. This turns the real hand
        // shape into a real grip.
        let fingers: [[Int]] = [[1,2,3,4],[5,6,7,8],[9,10,11,12],[13,14,15,16],[17,18,19,20]]
        for (fi, chain) in fingers.enumerated() {
            let isThumb = fi == 0
            var origin = local[chain[0]]
            // Initial bone direction in this frame.
            var dir = simd_normalize(local[chain[1]] - local[chain[0]])
            var cumulative: Float = isThumb ? 0.35 : 0.55   // radians per joint
            for k in 0..<(chain.count - 1) {
                let a = chain[k], b = chain[k + 1]
                let boneLen = simd_length(local[b] - local[a])
                // Rotate the bone direction toward the palm (+Z) around the knuckle axis (X).
                let ang = cumulative
                let rotAxis = SIMD3<Float>(1, 0, 0)
                let q = simd_quatf(angle: ang, axis: rotAxis)
                dir = simd_act(q, dir)
                let newB = origin + dir * boneLen
                local[b] = newB
                origin = newB
                cumulative += isThumb ? 0.25 : 0.6
            }
        }
        return local.map { SCNVector3($0.x, $0.y, $0.z) }
    }

    /// Build a hand from 21 local joint positions: emissive joint spheres + tapered bone
    /// capsules. The taper (wrist thick → fingertip thin) gives real finger volume.
    private static func buildHand(local: [SCNVector3], color: UIColor) -> SCNNode {
        let node = SCNNode()
        func mat() -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color.withAlphaComponent(0.30)
            m.emission.contents = color.withAlphaComponent(0.85)
            m.transparency = 0.66
            m.transparencyMode = .dualLayer
            m.lightingModel = .constant
            m.isDoubleSided = true
            return m
        }
        let rScale: Float = 0.24

        // Joints — spheres sized per landmark.
        for (i, p) in local.enumerated() {
            let s = SCNSphere(radius: CGFloat(GripReferencePose.radius(i) * rScale))
            s.segmentCount = 20
            s.materials = [mat()]
            let jn = SCNNode(geometry: s); jn.position = p
            node.addChildNode(jn)
        }
        // Bones — capsules between connected joints (radius = thinner endpoint).
        for (a, b) in GripReferencePose.connections {
            guard a < local.count, b < local.count else { continue }
            let pa = local[a], pb = local[b]
            let d = SCNVector3(pb.x - pa.x, pb.y - pa.y, pb.z - pa.z)
            let len = sqrtf(d.x*d.x + d.y*d.y + d.z*d.z)
            guard len > 0.001 else { continue }
            let r = min(GripReferencePose.radius(a), GripReferencePose.radius(b)) * rScale * 0.9
            let cap = SCNCapsule(capRadius: CGFloat(r), height: CGFloat(len))
            cap.materials = [mat()]
            let bn = SCNNode(geometry: cap)
            bn.position = SCNVector3((pa.x+pb.x)/2, (pa.y+pb.y)/2, (pa.z+pb.z)/2)
            // Orient the capsule's local +Y axis along the bone direction.
            bn.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0),
                                            to: simd_normalize(SIMD3<Float>(d.x, d.y, d.z)))
            node.addChildNode(bn)
        }
        return node
    }
}
