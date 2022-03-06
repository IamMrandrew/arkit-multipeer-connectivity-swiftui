//
//  ContentView.swift
//  ARDemo
//
//  Created by Andrew Li on 5/3/2022.
//

import SwiftUI
import RealityKit
import ARKit

struct ContentView : View {
    @StateObject var vm = ARViewModel()
    
    var body: some View {
        return ZStack {
            ARViewContainer()
                .edgesIgnoringSafeArea(.all)
                .environmentObject(vm)
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject var vm: ARViewModel
    
    typealias UIViewType = ARView
    
    func makeUIView(context: Context) -> ARView {        
        vm.arView.session.delegate = context.coordinator
        
        return vm.arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
    }
}

extension ARView {
    // Extned ARView to implement tapGesture handler
    // Hybrid workaround between UIKit and SwiftUI
    
    func enableTapGesture() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(recognizer:)))
        self.addGestureRecognizer(tapGestureRecognizer)
    }
    
    @objc func handleTap(recognizer: UITapGestureRecognizer) {
        let tapLocation = recognizer.location(in: self)
                            
        // Attempt to find a 3D location on a horizontal surface underneath the user's touch location.
        let results = self.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .any)
        
        if let firstResult = results.first {
            // Add an ARAnchor at the touch location with a special name you check later in `session(_:didAdd:)`.
            let anchor = ARAnchor(name: "toy_drummer", transform: firstResult.worldTransform)
            self.session.add(anchor: anchor)
        } else {
            print("Warning: Object placement failed.")
        }
    }
    
    func placeSceneObject(named entityName: String, for anchor: ARAnchor){
        let entity = try! ModelEntity.loadModel(named: entityName)
        
        entity.generateCollisionShapes(recursive: true)
        self.installGestures([.all], for: entity)
        
        let anchorEntity = AnchorEntity(anchor: anchor)
        anchorEntity.addChild(entity)
        self.scene.addAnchor(anchorEntity)
    }
}

extension ARViewContainer {
    // Communicate changes from UIView to SwiftUI by updating the properties of your coordinator
    // Confrom the coordinator to ARSessionDelegate
    
    class Coordinator: NSObject, ARSessionDelegate {
        var parent: ARViewContainer
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
                
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {                
                if let participantAnchor = anchor as? ARParticipantAnchor{
                    print("Established joint experience with a peer.")
                    
                    let anchorEntity = AnchorEntity(anchor: participantAnchor)
                    let mesh = MeshResource.generateSphere(radius: 0.03)
                    let color = UIColor.red
                    let material = SimpleMaterial(color: color, isMetallic: false)
                    let coloredSphere = ModelEntity(mesh:mesh, materials:[material])
                    
                    anchorEntity.addChild(coloredSphere)
                    
                    self.parent.vm.arView.scene.addAnchor(anchorEntity)
                } else {
                    if let anchorName = anchor.name, anchorName == "toy_drummer"{
                        self.parent.vm.arView.placeSceneObject(named: anchorName, for: anchor)
                    }
                }
            }
        }
        
        func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
            guard let multipeerSession = self.parent.vm.multipeerSession else { return }
            if !multipeerSession.connectedPeers.isEmpty {
                guard let encodedData = try? NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
                else { fatalError("Unexpectedly failed to encode collaboration data.") }
                // Use reliable mode if the data is critical, and unreliable mode if the data is optional.
                let dataIsCritical = data.priority == .critical
                multipeerSession.sendToAllPeers(encodedData, reliably: dataIsCritical)
            } else {
                print("Deferred sending collaboration to later because there are no peers.")
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
}



#if DEBUG
struct ContentView_Previews : PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ARViewModel())
    }
}
#endif
