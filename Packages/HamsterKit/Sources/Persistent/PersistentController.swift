//
//  PersistentController.swift
//  HamsterApp
//
//  Created by morse on 16/3/2023.
//

import CoreData

struct PersistentController {
  static let shared = Result { try PersistentController() }

  let container: NSPersistentContainer
  init() throws {
    let name = "HamsterApp"

    let storeURL = try AppGroupAccess.requireContainer()
      .appendingPathComponent("\(name).sqlite")

    let storeDescription = NSPersistentStoreDescription(url: storeURL)
    container = NSPersistentContainer(name: name)
    container.persistentStoreDescriptions = [storeDescription]
    container.loadPersistentStores { _, error in
      if let error = error as NSError? {
        NSLog("Shared persistent store failed to load (code: %ld)", error.code)
      }
    }
  }
}
