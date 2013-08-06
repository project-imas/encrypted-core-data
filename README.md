# Encrypted Core Data SQLite Store

Provides a Core Data store that encrypts all data that is persisted.  Besides the initial setup, the usage is exactly the same as Core Data and can be used in existing projects that use Core Data.

# Vulnerabilities Addressed

1. SQLite database is not encrypted, contents are in plain text
  - CWE-311: Missing Encryption of Sensitive Data
2. SQLite database file protected with 4 digit system passcode
  - CWE-326: Inadequate Encryption Strength
  - SRG-APP-000129-MAPP-000029  Severity-CAT II: The mobile application must implement automated mechanisms to enforce access control restrictions which are not provided by the operating system

# Project Setup
  * When creating the project make sure **Use Core Data** is selected
  * Follow the [SQLCipher for iOS](http://sqlcipher.net/ios-tutorial/) setup guide
  * Switch into your project's root directory and checkout the encrypted-core-data project code
```
    cd ~/Documents/code/YourApp

    git clone https://github.com/project-imas/encrypted-core-data.git
```
  * Click on the top level Project item and add files ("option-command-a")
  * Navigate to **encrypted-core-data**, highlight **Incremental Store**, and click **Add**

# Using EncryptedStore

In your application delegate source file (i.e. AppDelegate.m) you should see
```objc
NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
```
replace that line with
```objc
NSPersistentStoreCoordinator *coordinator = [EncryptedStore makeStore:[self managedObjectModel]:@"SOME_PASSWORD"];
```

Replacing **SOME_PASSWORD** with an actual password.

Also in the same file add an import for EncryptedStore.h:
```objc
   #import "EncryptedStore.h"
```

If there are issues you can add `-com.apple.CoreData.SQLDebug 1` to see all statements encryted-cored-data generates be logged.

# Features

- One-to-one relationships
- One-to-many relationships
- Many-to-many relationships
- Predicates
- Inherited entities (Thanks to [NachoMan](https://github.com/NachoMan/)) 

Missing features and known bugs are maintained on the [issue tracker](https://github.com/project-imas/encrypted-core-data/issues?state=open)

# Diagram

Below is a diagram showing the differences between NSSQLiteStore and EncryptedStore.  Note that actual the SQLite calls are coupled fairly strongly with the layer wrapping it:
<img src="diagram.jpg" />


# Strings Comparison

Below is the output of doing the unix *strings* command on a sample applications .sqlite file.  As you can see, the default persistence store leaves all information in plaintext:
<img src="stringOutput.jpg" />


## License

Copyright 2012 The MITRE Corporation, All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this work except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

[![githalytics.com alpha](https://cruel-carlota.pagodabox.com/50cf88b71d3c78a0268ae42ea79d8951 "githalytics.com")](http://githalytics.com/project-imas/encrypted-core-data)


