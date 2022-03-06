//
//  ARViewModel.swift
//  ARDemo
//
//  Created by Andrew Li on 6/3/2022.
//

import SwiftUI
import RealityKit
import ARKit
import MultipeerConnectivity

class ARViewModel: ObservableObject {
    @Published var arView: ARView!
    @Published var multipeerSession: MultipeerSession?
    @Published var sessionIDObservation: NSKeyValueObservation?
    
    // A dictionary to map MultiPeer IDs to ARSession ID's.
    // This is useful for keeping track of which peer created which ARAnchors.
    var peerSessionIDs = [MCPeerID: String]()
    
    init() {
        arView = ARView(frame: .zero)
        
        // Turn off ARView's automatically-configured session
        // to create and set up your own configuration.
        arView.automaticallyConfigureSession = false
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        // Enable a collaborative session.
        config.isCollaborationEnabled = true
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        // Begin the session.
        arView.session.run(config)
        
        // Setup a coaching overlay
        let coachingOverlay = ARCoachingOverlayView()

        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .horizontalPlane
        
        arView.addSubview(coachingOverlay)
        
        // Use key-value observation to monitor your ARSession's identifier.
        sessionIDObservation = arView.session.observe(\.identifier, options: [.new]) { object, change in
            print("SessionID changed to: \(change.newValue!)")
            // Tell all other peers about your ARSession's changed ID, so
            // that they can keep track of which ARAnchors are yours.
            guard let multipeerSession = self.multipeerSession else { return }
            self.sendARSessionIDTo(peers: multipeerSession.connectedPeers)
        }
        
        // Start looking for other players via MultiPeerConnectivity.
        multipeerSession = MultipeerSession(receivedDataHandler: self.receivedData, peerJoinedHandler: self.peerJoined, peerLeftHandler: peerLeft, peerDiscoveredHandler: peerDiscovered)
        
        // Add tap gesture for placing blocks
        arView.enableTapGesture()
    }
}

extension ARViewModel {
    private func sendARSessionIDTo(peers: [MCPeerID]) {
        guard let multipeerSession = multipeerSession else { return }
        let idString = arView.session.identifier.uuidString
        let command = "SessionID:" + idString
        if let commandData = command.data(using: .utf8) {
            multipeerSession.sendToPeers(commandData, reliably: true, peers: peers)
        }
    }
    
    func receivedData(_ data: Data, from peer: MCPeerID) {
        if let collaborationData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARSession.CollaborationData.self, from: data) {            
            arView.session.update(with: collaborationData)
            return
        }
        // ...
        let sessionIDCommandString = "SessionID:"
        if let commandString = String(data: data, encoding: .utf8), commandString.starts(with: sessionIDCommandString) {
            let newSessionID = String(commandString[commandString.index(commandString.startIndex,
                                                                     offsetBy: sessionIDCommandString.count)...])
            // If this peer was using a different session ID before, remove all its associated anchors.
            // This will remove the old participant anchor and its geometry from the scene.
            if let oldSessionID = peerSessionIDs[peer] {
                removeAllAnchorsOriginatingFromARSessionWithID(oldSessionID)
            }
            
            peerSessionIDs[peer] = newSessionID
        }
    }
    
    func peerDiscovered(_ peer: MCPeerID) -> Bool {
        guard let multipeerSession = multipeerSession else { return false }
        
        if multipeerSession.connectedPeers.count > 4 {
            // Do not accept more than four users in the experience.
            print("A fifth peer wants to join the experience.\nThis app is limited to four users.")
            return false
        } else {
            return true
        }
    }
    /// - Tag: PeerJoined
    func peerJoined(_ peer: MCPeerID) {
        print("""
            A peer wants to join the experience.
            Hold the phones next to each other.
            """)
        // Provide your session ID to the new user so they can keep track of your anchors.
        sendARSessionIDTo(peers: [peer])
    }
        
    func peerLeft(_ peer: MCPeerID) {
        print("A peer has left the shared experience.")
        
        // Remove all ARAnchors associated with the peer that just left the experience.
        if let sessionID = peerSessionIDs[peer] {
            removeAllAnchorsOriginatingFromARSessionWithID(sessionID)
            peerSessionIDs.removeValue(forKey: peer)
        }
    }
    
    private func removeAllAnchorsOriginatingFromARSessionWithID(_ identifier: String) {
        guard let frame = arView.session.currentFrame else { return }
        for anchor in frame.anchors {
            guard let anchorSessionID = anchor.sessionIdentifier else { continue }
            if anchorSessionID.uuidString == identifier {
                arView.session.remove(anchor: anchor)
            }
        }
    }
}
