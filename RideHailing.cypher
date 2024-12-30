// You can run this full script at once or comamnd-by-command (copy and past it on the Neo4j Brwoser command line)

// Lets Clear all Nodes and Relatioships before we start   

MATCH (n) DETACH DELETE n; 
DROP CONSTRAINT unique_car IF EXISTS;
DROP CONSTRAINT unique_driver IF EXISTS;
DROP CONSTRAINT unique_passenger IF EXISTS;
DROP CONSTRAINT unique_booking IF EXISTS;
DROP CONSTRAINT unique_GeoHash IF EXISTS;


// *************  Graph Data Model (aka INFORMATION ARCHITECTURE)  *************
 

// Create Passengers Domain Collection 

CREATE (:PassengerS {Name: "PassengerS"}) ;
CREATE (:AddresseS {Name: "AddresseS"}) ;

// Passengers are Proper Nouns, so we set a Unique Constraint on the Phone (we will use the Phone number as a customer id in this Demo)

CREATE CONSTRAINT unique_passenger IF NOT EXISTS
FOR (n:Passenger)
REQUIRE n.Phone IS UNIQUE;  

// Address (GeoHash) is a Proper Noun, so we set a Unique Constraint on the GeoHash 

 CREATE CONSTRAINT unique_GeoHash IF NOT EXISTS
 FOR (a:Address)
 REQUIRE a.GeoHash IS UNIQUE;  


// Create/test one Passenger Structure: Connect Passenger to individual HistorY collection, Connect Passenger to individual WalleT collection, Connect Passenger to individual AddressBooK collection, Connect Passenger to PasengerS collection   

// Passenger creation with PaymentMethod and Address collections

MATCH (ps:PassengerS) 
CREATE  (ps)-[:HAS]->(p:Passenger {Name: "Antonio", Phone: "23456683", Email: "Antonio@email.com" , Photo: "https://photos.com/img/Antonio.jpg"})-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), 
(p)-[:HAS_WALLET]->(w:WalleT {Name: "WalleT"})-[:HAS]->(pm1:PaymentMethod {Type: "CreditCard", Issuer: "MasterCard", NameOnCard: "Antonio Banderas", CardNumber: 5590120400002540, ExpDate: "08/26", CVV: 321}),
(w)-[:HAS]->(pm2:PaymentMethod {Type: "DebitCard", Issuer: "Visa", NameOnCard: "Antonio Banderas", CardNumber: 4701322211111234, ExpDate: "12/26", CVV: 837}),
(p)-[:HAS_PREFERED_PAYMENT]->(pm1),
(p)-[:HAS_ADDRESS]->(ab:AddressBooK {Name:"AddressBooK"});

// For this first Passenger, we will create a Home and Work addresses entry in the Address Book collection and connect them to the respective GeoHash (http://geohash.co/) Address that will be connected to the AddresseS collection  

// We check if the GeoHash already exists in the AddresseS collection

MATCH (a:Address {GeoHash: "9xj3gen11ug3"}) RETURN count(a);

// IF the GeoHAsh already exists (count(a) = 1) we connect it the Passengers Address book entry using the Name provided by the Passenger  

MATCH (a:Address {GeoHash: "9xj3gen11ug3"}), (p:Passenger {Phone: "23456683"} )-[:HAS_ADDRESS]->(ab:AddressBooK {Name:"AddressBooK"})
MERGE (ab)-[:HAS]->(:FavAddress {Name: "Home"})-[:IS_ADDRESS]->(a);
//If you execute the above Cypher command, as the MATCH for the GeoHash does not return any records, the MERGE instruction will not execute 

// ELSE if the GeoHash does not exist (count(a) = 0) we create a new GeoHash Node, connect it to the AddresseS collection and to the Passengers Address book entry using the Name provided by the Passenger

MATCH (p:Passenger {Phone: "23456683"} )-[:HAS_ADDRESS]->(ab:AddressBooK {Name:"AddressBooK"}), (ad:AddresseS)
MERGE (ab)-[:HAS]->(:FavAddress {Name: "Home"})-[:IS_ADDRESS]->(:Address {GeoHash: "9xj3gen11ug3", StreetNum: 950, StreetName: "S Elizabeth St", City: "Denver", State: "CO", ZIP: 80209})<-[:HAS]-(ad);

// Create an Office address entry in the Address Book collection and connect it to the respective GeoHash (http://geohash.co/) Address that will be connected to the AddresseS collection  

// We check if the GeoHash already exists in the AddresseS collection

MATCH (a:Address {GeoHash: "9xj64g7vxjtr"}) RETURN count(a);

// IF the GeoHAsh already exists (count(a) = 1) we connect it the Passengers Address book entry using the Name provided by the Passenger  

MATCH (a:Address {GeoHash: "9xj64g7vxjtr"}), (p:Passenger {Phone: "23456683"} )-[:HAS_ADDRESS]->(ab:AddressBooK {Name:"AddressBooK"})
MERGE (ab)-[:HAS]->(:FavAddress {Name: "Work"})-[:IS_ADDRESS]->(a);
//If you execute the above Cypher command, as the MATCH for the GeoHash does not return any records, the MERGE instruction will not execute

// ELSE if the GeoHash does not exist (count(a) = 0), we create a new GeoHash Node, connect it to the AddresseS collection and the Passengers Address book entry using the Name provided by the Passenger

MATCH (p:Passenger {Phone: "23456683"} )-[:HAS_ADDRESS]->(ab:AddressBooK {Name:"AddressBooK"}), (ad:AddresseS)
MERGE (ab)-[:HAS]->(:FavAddress {Name: "Work"})-[:IS_ADDRESS]->(a:Address {GeoHash: "9xj64g7vxjtr", StreetNum: 600, StreetName: "17th St", City: "Denver", State: "CO", ZIP: 80202})<-[:HAS]-(ad);



// Creation of the entire Passenger structure, with two Payment Methods, one preferred Payment Method, and two Addresses (create 10 nodes, 13 relationships, and 33 properties)


MATCH (ps:PassengerS), (ad:AddresseS)
CREATE  (ps)-[:HAS]->(p:Passenger {Name: "Peter", Phone: "98456683", Email: "Peter@email.com" , Photo: "https://photos.com/img/Peter.jpg"})-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), 
(p)-[:HAS_WALLET]->(w:WalleT {Name: "WalleT"})-[:HAS]->(pm1:PaymentMethod {Type: "CreditCard", Issuer: "MasterCard", NameOnCard: "Peter Pan", CardNumber: 2222420000001113, ExpDate: "08/26", CVV: 321}),
(w)-[:HAS]->(pm2:PaymentMethod {Type: "DebitCard", Issuer: "Visa", NameOnCard: "Peter Pan", CardNumber: 4512954215235590, ExpDate: "12/26", CVV:291}),
(w)-[:HAS]->(pm3:PaymentMethod {Type: "Cash"}),
(p)-[:HAS_PREFERED_PAYMENT]->(pm1),
(p)-[:HAS_ADDRESS]->(ab:AddressBooK {Name:"AddressBooK"})-[:HAS]->(:FavAddress {Name: "Home"})-[:IS_ADDRESS]->(:Address {GeoHash: "9xj6hs9cxw65", StreetNum: 2315, StreetName: "Krameria St", City: "Denver", State: "CO", ZIP: 80207})<-[:HAS]-(ad),
(ab)-[:HAS]->(:FavAddress {Name: "Work"})-[:IS_ADDRESS]->(:Address {GeoHash: "9xj6kq1xv0c2", StreetNum: 5990, StreetName: "Dahlia St", City: "Commerce City", State: "CO", ZIP: 80022})<-[:HAS]-(ad);




// Query the Passenger just Created and check the Structure on the Graph Explorer 

MATCH (p:Passenger {Phone: "98456683"}) RETURN p;


// Create Car Domain Collections 

CREATE (f:FleeT {Name: "FleeT"}), 
       (a:AvailablE {Name: "AvailablE"})<-[:HAS]-(f), 
       (b:BusY {Name: "BusY"})<-[:HAS]-(f), 
       (m:MaintenancE {Name: "MaintenancE"})<-[:HAS]-(f), 
       (o:OffDutY {Name: "OffDutY"})<-[:HAS]-(f), 
       (r:RetireD {Name: "RetireD"})<-[:HAS]-(f),
       (p:PendinG {Name: "PendinG"})<-[:HAS]-(f),
       (j:RejecteD {Name: "RejecteD"})<-[:HAS]-(f); 

// Create Drivers Domain Collections 

CREATE (d:DriverS {Name: "DriverS"});

// Car and Driver are Proper Nouns so we set a Unique Constrain - We will use the Car licence Plate as the ID for Car and and the Drivers ID as the ID in this Demo

CREATE CONSTRAINT unique_car IF NOT EXISTS
FOR (n:Car)
REQUIRE n.Plate IS UNIQUE;

CREATE CONSTRAINT unique_driver  IF NOT EXISTS
FOR (n:Driver)
REQUIRE n.ID IS UNIQUE;


// Create one Driver structure with Wallet, History, and its respective Car with the initial Location (Loc) and connect the Driver to the Car and vice-versa. Place the Car in the Peding Collection

OPTIONAL MATCH (p:PendinG {Name: "PendinG"}), (dc:DriverS {Name: "DriverS"})
CREATE  (d1:Driver {Name: "Albert", ID: "S12345678N", License: "SG144445578", Phone: "443344331", Email: "Albert@email.com" , Photo: "https://photos.com/img/Albert.jpg" })-[:HAS_CAR]->(c1:Car { Plate: "ABC-1234", Make: "Toyota", Model:"Prius", Year: 2022, Capacity: 4, Color: "White"})-[:HAS_DRIVER]->(d1), 
(d1)<-[:HAS]-(dc), 
(d1)-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), 
(d1)-[:HAS_WALLET]->(w:WalleT {Name: "WalleT"})-[:HAS]->(cm1:CreditMethod {Type: "Bank Tranfer", AccName: "Albert Smith" , AccNumber: 9488477223, SWIFT_BIC: "CITIUSCODV"}),
(d1)-[:HAS_PREFERED_CREDIT]->(cm1),
(c1)-[:IS_AT]->(:Loc {GeoHash: "9xj3fc4xfeyx" , Time: localdatetime.transaction()}),
(c1)<-[:HAS]-(p);


// Query the car just ceated and check the structure on the Graph Explorer 

MATCH (c:Car {Plate:"ABC-1234"}) RETURN c; 


// Create the Booking Domain Collections 

CREATE (b:BookingS {Name: "BookingS"}), 
       (:ActivE {Name: "ActivE"})<-[:HAS]-(b),
       (:PasT {Name: "PasT"})<-[:HAS]-(b), 
       (:WaitinG {Name: "WaitinG"})<-[:HAS]-(b), 
       (:CanceleD {Name: "CanceleD"})<-[:HAS]-(b);

// A Booking is a Proper Noun, so we set a Unique Constraint  - The system will need a Microservice to generate unique BookingID's; we will create manual ones for this Demo mockup

CREATE CONSTRAINT unique_booking  IF NOT EXISTS
FOR (n:Booking)
REQUIRE n.BookingID IS UNIQUE; 








// *************  Interaction Model (aka  INTERACTION ARCHITECTURE )  *************



// Create 9 Cars, 9  Drivers, Connect Cars to PendiG collection, Connect Cars to individual HistorY collection, Connect Cars to individual Location node, Connect Driver to DriverS collection 

OPTIONAL MATCH (p:PendinG {Name: "PendinG"}), (dc:DriverS {Name: "DriverS"})
CREATE  (d2:Driver {Name: "Brandon", ID: "S84765968N", License: "SG454435548", Phone: "944453321", Email: "Brandon@email.com" , Photo: "https://photos.com/img/Brandon.jpg"})-[:HAS_CAR]->(c2:Car { Plate: "ABC-5678", Make: "Honda", Model:"Vezel", Year: 2021, Capacity: 4, Color: "Red"})-[:HAS_DRIVER]->(d2), (c2)<-[:HAS]-(p), (d2)<-[:HAS]-(dc) , (d2)-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (d2)-[:HAS_WALLET]->(:WalleT {Name: "WalleT"}), (c2)-[:IS_AT]->(:Loc {GeoHash: "9xj3fc4xfeyx" , Time: localdatetime.transaction()}),
        (d3:Driver {Name: "Charles", ID: "S324538736N", License: "SG35664433", Phone: "997766544", Email: "Charles@email.com" , Photo: "https://photos.com/img/Charles.jpg" })-[:HAS_CAR]->(c3:Car { Plate: "ABD-1234", Make: "Toyota", Model:"Corolla", Year: 2023, Capacity: 4, Color: "Blue"})-[:HAS_DRIVER]->(d3), (c3)<-[:HAS]-(p), (d3)<-[:HAS]-(dc) , (d3)-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (d3)-[:HAS_WALLET]->(:WalleT {Name: "WalleT"}), (c3)-[:IS_AT]->(:Loc {GeoHash: "9xj3f3yvpp2c" , Time: localdatetime.transaction()}),
        (d4:Driver {Name: "Donald", ID: "S67828333N", License: "SG876443334", Phone: "944455541", Email: "Donald@email.com" , Photo: "https://photos.com/img/Donald.jpg"})-[:HAS_CAR]->(c4:Car { Plate: "ABD-5678", Make: "Toyota", Model:"C-HR", Year: 2019, Capacity: 4, Color: "Green"})-[:HAS_DRIVER]->(d4), (c4)<-[:HAS]-(p), (d4)<-[:HAS]-(dc) , (d4)-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (d4)-[:HAS_WALLET]->(:WalleT {Name: "WalleT"}), (c4)-[:IS_AT]->(:Loc {GeoHash: "9xj3f3m219hj" , Time: localdatetime.transaction()}),
        (d5:Driver {Name: "Eduard", ID: "S98376432N", License: "SG865434938", Phone: "955445551", Email: "Eduard@email.com" , Photo: "https://photos.com/img/Eduard.jpg"})-[:HAS_CAR]->(c5:Car { Plate: "ABE-1234", Make: "Toyota", Model:"Prius", Year: 2020, Capacity: 4, Color: "White"})-[:HAS_DRIVER]->(d5), (c5)<-[:HAS]-(p), (d5)<-[:HAS]-(dc) , (d5)-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (d5)-[:HAS_WALLET]->(:WalleT {Name: "WalleT"}), (c5)-[:IS_AT]->(:Loc {GeoHash: "9xj3g789wbtx" , Time: localdatetime.transaction()}),
        (d6:Driver {Name: "Frank", ID: "S25984432N", License: "SG14564336", Phone: "909876665", Email: "Frank@email.com" , Photo: "https://photos.com/img/Frank.jpg"})-[:HAS_CAR]->(c6:Car { Plate: "ABE-5678", Make: "Honda", Model:"Freed", Year: 2022, Capacity: 4, Color: "Black"})-[:HAS_DRIVER]->(d6), (c6)<-[:HAS]-(p), (d6)<-[:HAS]-(dc) , (d6)-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (d6)-[:HAS_WALLET]->(:WalleT {Name: "WalleT"}), (c6)-[:IS_AT]->(:Loc {GeoHash: "9xj3gq7rw9p4" , Time: localdatetime.transaction()}),
        (d7:Driver {Name: "Gilbert", ID: "S093983333N", License: "SG94877448", Phone: "55446773", Email: "Gilbert@email.com" , Photo: "https://photos.com/img/Gilbert.jpg"})-[:HAS_CAR]->(c7:Car { Plate: "ABF-1234", Make: "Toyota", Model:"C-HR", Year: 2021, Capacity: 4, Color: "Yellow"})-[:HAS_DRIVER]->(d7), (c7)<-[:HAS]-(p), (d7)<-[:HAS]-(dc) , (d7)-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (d7)-[:HAS_WALLET]->(:WalleT {Name: "WalleT"}), (c7)-[:IS_AT]->(:Loc {GeoHash: "9xj64mn04zdd" , Time: localdatetime.transaction()}),
        (d8:Driver {Name: "Harold", ID: "S763663638N", License: "SG4454433", Phone: "484747443", Email: "Harold@email.com" , Photo: "https://photos.com/img/Harold.jpg"})-[:HAS_CAR]->(c8:Car { Plate: "ABF-5678", Make: "Honda", Model:"Civic", Year: 2019, Capacity: 4, Color: "Red"})-[:HAS_DRIVER]->(d8), (c8)<-[:HAS]-(p), (d8)<-[:HAS]-(dc) , (d8)-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (d8)-[:HAS_WALLET]->(:WalleT {Name: "WalleT"}), (c8)-[:IS_AT]->(:Loc {GeoHash: "9xj67ser8kcb" , Time: localdatetime.transaction()}),
        (d9:Driver {Name: "Ingrid", ID: "S18487473N", License: "SG55678943", Phone: "998474731", Email: "Ingrid@email.com" , Photo: "https://photos.com/img/Ingrid.jpg"})-[:HAS_CAR]->(c9:Car { Plate: "ABG-1234", Make: "Toyota", Model:"Sienna", Year: 2022, Capacity: 4, Color: "Blue"})-[:HAS_DRIVER]->(d9), (c9)<-[:HAS]-(p), (d9)<-[:HAS]-(dc) , (d9)-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (d9)-[:HAS_WALLET]->(:WalleT {Name: "WalleT"}), (c9)-[:IS_AT]->(:Loc {GeoHash: "9xj6mndvvcpq" , Time: localdatetime.transaction()}),
        (d10:Driver {Name: "Juliet", ID: "S17477328N", License: "SG12379744", Phone: "998474744", Email: "Juliet@email.com" , Photo: "https://photos.com/img/Juliet.jpg" })-[:HAS_CAR]->(c10:Car { Plate: "ABG-5678", Make: "Toyota", Model:"Hilux", Year: 2023, Capacity: 4, Color: "White"})-[:HAS_DRIVER]->(d10), (c10)<-[:HAS]-(p), (d10)<-[:HAS]-(dc) , (d10)-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (d10)-[:HAS_WALLET]->(:WalleT {Name: "WalleT"}), (c10)-[:IS_AT]->(:Loc {GeoHash: "9xj70j09fu78" , Time: localdatetime.transaction()}) ;

// Cypher command to Updating a Car current location from time to time - The system will need a Microservice to generate the GeoHash of the current car location based on GPS Latitude and Longitude

//Using the Car as anchor:

MATCH (c:Car {Plate: "ABF-5678"})-[IS_AT]->(l:Loc)
SET l.GeoHash = "9xj70hjbrgtu", l.Time = datetime();

// Using the Driver as anchor:

MATCH (d:Driver {ID:"S12345678N"})-[HAS_CAR]-()-[IS_AT]->(l:Loc)
SET l.GeoHash = "9xj70hjbrgtu", l.Time = datetime();



// After validating a Car<->Driver, we move them to the AvailablE collection so they can start receiving Booking requests and serving Passengers 

MATCH (c:Car { Plate: "ABC-1234"})<-[r1:HAS]-(p:PendinG {Name:"PendinG"}), (a:AvailablE {Name: "AvailablE"}) CREATE (c)<-[r2:HAS]-(a) DELETE r1; 

MATCH (c:Car { Plate: "ABC-5678"})<-[r1:HAS]-(p:PendinG {Name:"PendinG"}), (a:AvailablE {Name: "AvailablE"}) CREATE (c)<-[r2:HAS]-(a) DELETE r1; 
MATCH (c:Car { Plate: "ABD-1234"})<-[r1:HAS]-(p:PendinG {Name:"PendinG"}), (a:AvailablE {Name: "AvailablE"}) CREATE (c)<-[r2:HAS]-(a) DELETE r1; 
MATCH (c:Car { Plate: "ABE-1234"})<-[r1:HAS]-(p:PendinG {Name:"PendinG"}), (a:AvailablE {Name: "AvailablE"}) CREATE (c)<-[r2:HAS]-(a) DELETE r1; 
MATCH (c:Car { Plate: "ABE-5678"})<-[r1:HAS]-(p:PendinG {Name:"PendinG"}), (a:AvailablE {Name: "AvailablE"}) CREATE (c)<-[r2:HAS]-(a) DELETE r1; 
MATCH (c:Car { Plate: "ABF-1234"})<-[r1:HAS]-(p:PendinG {Name:"PendinG"}), (a:AvailablE {Name: "AvailablE"}) CREATE (c)<-[r2:HAS]-(a) DELETE r1; 
MATCH (c:Car { Plate: "ABF-5678"})<-[r1:HAS]-(p:PendinG {Name:"Pending"}), (a:AvailablE {Name: "AvailablE"}) CREATE (c)<-[r2:HAS]-(a) DELETE r1; 
MATCH (c:Car { Plate: "ABG-1234"})<-[r1:HAS]-(p:PendinG {Name:"PendinG"}), (a:AvailablE {Name: "AvailablE"}) CREATE (c)<-[r2:HAS]-(a) DELETE r1; 
MATCH (c:Car { Plate: "ABG-5678"})<-[r1:HAS]-(p:PendinG {Name:"PendinG"}), (a:AvailablE {Name: "AvailablE"}) CREATE (c)<-[r2:HAS]-(a) DELETE r1; 

// We will Reject Car {Plate: "ABD-5678"} application. So we disconnect it from the PendinG collection and connect it to the RejecteD collection for the record/auditing 

MATCH (c:Car {Plate: "ABD-5678"})<-[r1:HAS]-(p:PendinG {Name:"PendinG"}), (j:RejecteD {Name: "RejecteD"}) 
CREATE (c)<-[r2:HAS]-(j) 
DELETE r1; 


// Create 10 Passengers structures: Connect Passenger to individual HistorY collection, Connect Passenger to individual WalleT collection, Connect Passenger to individual AddressBooK collection, Conenct Passenger to PasengerS collection   
// Passenger creation with PaymentMethod and Address placeholder Collections

MATCH (pc:PassengerS)
CREATE  (pc)-[:HAS]->(p2:Passenger {Name: "Benson", Phone: "40985343" , Email: "Benson@email.com" , Photo: "https://photos.com/img/Benson.jpg"})-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (p2)-[:HAS_WALLET]->(w2:WalleT {Name: "WalleT"})-[:HAS]->(pm2:PaymentMethod {Type: "CreditCard", Issuer: "MasterCard", NameOnCard: "Benson Tan", CardNumber: 5554740400899688, ExpDate: "08/26", CVV: 883}), (p2)-[:HAS_PREFERED_PAYMENT]->(pm2), (p2)-[:HAS_ADDRESS]->(:AddressBooK {Name:"AddressBooK"}), (w2)-[:HAS]->(:PaymentMethod {Type: "Cash"}),
        (pc)-[:HAS]->(p3:Passenger {Name: "Cleber", Phone: "56230987" , Email: "Cleber@email.com" , Photo: "https://photos.com/img/Cleber.jpg"})-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (p3)-[:HAS_WALLET]->(w3:WalleT {Name: "WalleT"})-[:HAS]->(pm3:PaymentMethod {Type: "CreditCard", Issuer: "MasterCard", NameOnCard: "Cleber Santos", CardNumber: 5590120400374378, ExpDate: "04/26", CVV: 700}), (p3)-[:HAS_PREFERED_PAYMENT]->(pm3), (p3)-[:HAS_ADDRESS]->(:AddressBooK {Name:"AddressBooK"}), (w3)-[:HAS]->(:PaymentMethod {Type: "Cash"}),
        (pc)-[:HAS]->(p4:Passenger {Name: "David", Phone: "29837442" , Email: "David@email.com" , Photo: "https://photos.com/img/David.jpg"})-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (p4)-[:HAS_WALLET]->(w4:WalleT {Name: "WalleT"})-[:HAS]->(pm4:PaymentMethod {Type: "CreditCard", Issuer: "MasterCard", NameOnCard: "David Copperland", CardNumber: 5590120400468360, ExpDate: "02/26", CVV: 126}), (p4)-[:HAS_PREFERED_PAYMENT]->(pm4), (p4)-[:HAS_ADDRESS]->(:AddressBooK {Name:"AddressBooK"}), (w4)-[:HAS]->(:PaymentMethod {Type: "Cash"}),
        (pc)-[:HAS]->(p5:Passenger {Name: "Ernest", Phone: "89207651" , Email: "Ernest@email.com" , Photo: "https://photos.com/img/Ernest.jpg"})-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (p5)-[:HAS_WALLET]->(w5:WalleT {Name: "WalleT"})-[:HAS]->(pm5:PaymentMethod {Type: "CreditCard", Issuer: "MasterCard", NameOnCard: "Ernest Hemingroad", CardNumber: 5590120400077120, ExpDate: "10/28", CVV: 664}), (p5)-[:HAS_PREFERED_PAYMENT]->(pm5), (p5)-[:HAS_ADDRESS]->(:AddressBooK {Name:"AddressBooK"}), (w5)-[:HAS]->(:PaymentMethod {Type: "Cash"}),
        (pc)-[:HAS]->(p6:Passenger {Name: "Frank", Phone: "78383822" , Email: "Frank@email.com" , Photo: "https://photos.com/img/Frank.jpg"})-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (p6)-[:HAS_WALLET]->(w6:WalleT {Name: "WalleT"})-[:HAS]->(pm6:PaymentMethod {Type: "CreditCard", Issuer: "MasterCard", NameOnCard: "Frank Zatta", CardNumber: 5590120400844131, ExpDate: "03/26", CVV: 493}), (p6)-[:HAS_PREFERED_PAYMENT]->(pm6), (p6)-[:HAS_ADDRESS]->(:AddressBooK {Name:"AddressBooK"}), (w6)-[:HAS]->(:PaymentMethod {Type: "Cash"}),
        (pc)-[:HAS]->(p7:Passenger {Name: "Gunter", Phone: "30982321" , Email: "Gunter@email.com" , Photo: "https://photos.com/img/Gunter.jpg"})-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (p7)-[:HAS_WALLET]->(w7:WalleT {Name: "WalleT"})-[:HAS]->(pm7:PaymentMethod {Type: "CreditCard", Issuer: "MasterCard", NameOnCard: "Gunter Schmidt", CardNumber: 5554740400521373, ExpDate: "05/26", CVV: 833}), (p7)-[:HAS_PREFERED_PAYMENT]->(pm7), (p7)-[:HAS_ADDRESS]->(:AddressBooK {Name:"AddressBooK"}), (w7)-[:HAS]->(:PaymentMethod {Type: "Cash"}),
        (pc)-[:HAS]->(p8:Passenger {Name: "Herbert", Phone: "78323862" , Email: "Herbert@email.com" , Photo: "https://photos.com/img/Herbert.jpg"})-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (p8)-[:HAS_WALLET]->(w8:WalleT {Name: "WalleT"})-[:HAS]->(pm8:PaymentMethod {Type: "CreditCard", Issuer: "MasterCard", NameOnCard: "Herbert Richards", CardNumber: 5590120400473279, ExpDate: "07/26", CVV: 287}), (p8)-[:HAS_PREFERED_PAYMENT]->(pm8), (p8)-[:HAS_ADDRESS]->(:AddressBooK {Name:"AddressBooK"}), (w8)-[:HAS]->(:PaymentMethod {Type: "Cash"}),
        (pc)-[:HAS]->(p9:Passenger {Name: "Igor", Phone: "40989221" , Email: "Igor@email.com" , Photo: "https://photos.com/img/Igor.jpg"})-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (p9)-[:HAS_WALLET]->(w9:WalleT {Name: "WalleT"})-[:HAS]->(pm9:PaymentMethod {Type: "CreditCard", Issuer: "MasterCard", NameOnCard: "Igor Stravonsky", CardNumber: 5554740400770046, ExpDate: "08/27", CVV: 357}), (p9)-[:HAS_PREFERED_PAYMENT]->(pm9), (p9)-[:HAS_ADDRESS]->(:AddressBooK {Name:"AddressBooK"}), (w9)-[:HAS]->(:PaymentMethod {Type: "Cash"}),
        (pc)-[:HAS]->(p10:Passenger {Name: "John", Phone: "94003822" , Email: "John@email.com" , Photo: "https://photos.com/img/John.jpg"})-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (p10)-[:HAS_WALLET]->(w10:WalleT {Name: "WalleT"})-[:HAS]->(pm10:PaymentMethod {Type: "CreditCard", Issuer: "MasterCard", NameOnCard: "John Lemon", CardNumber: 5554740400123295, ExpDate: "11/27", CVV: 488}), (p10)-[:HAS_PREFERED_PAYMENT]->(pm10), (p10)-[:HAS_ADDRESS]->(:AddressBooK {Name:"AddressBooK"}), (w10)-[:HAS]->(:PaymentMethod {Type: "Cash"}),
        (pc)-[:HAS]->(p11:Passenger {Name: "Karl", Phone: "820042321" , Email: "Karl@email.com", Photo: "https://photos.com/img/Karl.jpg" })-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), (p11)-[:HAS_WALLET]->(w11:WalleT {Name: "WalleT"})-[:HAS]->(pm11:PaymentMethod {Type: "CreditCard", Issuer: "MasterCard", NameOnCard: "Karl Mix", CardNumber: 5554740400497350, ExpDate: "12/28", CVV: 786}), (p11)-[:HAS_PREFERED_PAYMENT]->(pm11), (p11)-[:HAS_ADDRESS]->(:AddressBooK {Name:"AddressBooK"}), (w11)-[:HAS]->(:PaymentMethod {Type: "Cash"}); 
        


// Time to start Booking

// Let's Create some Random GeoHash Addresses to use later on our Demo

MATCH  (ad:AddresseS)
CREATE (:Address {GeoHash: "9xj70g6z1xry", StreetNum: 390, StreetName: "Hemlock St", City: "Denver", State: "CO", ZIP: 80200})<-[:HAS]-(ad),
       (:Address {GeoHash: "9xj6cvxyeen7", StreetNum: 3308, StreetName: "W 107th Ave", City: "Westminster", State: "CO", ZIP: 80031})<-[:HAS]-(ad),
       (:Address {GeoHash: "9xj6juhv9401", StreetNum: 2211, StreetName: "Lansing St", City: "Denver", State: "CO", ZIP: 80010})<-[:HAS]-(ad),
       (:Address {GeoHash: "9xj3duugfzhy", StreetNum: 2818, StreetName: "S Bannock S", City: "Denver", State: "CO", ZIP: 80110})<-[:HAS]-(ad),
       (:Address {GeoHash: "9xj3fuwsetzu", StreetNum: 476, StreetName: "S Broadway", City: "Denver", State: "CO", ZIP: 80209})<-[:HAS]-(ad),       
       (:Address {GeoHash: "9xj6508tghbr", StreetNum: 200, StreetName: "E 9th Ave", City: "Denver", State: "CO", ZIP: 80203})<-[:HAS]-(ad),
       (:Address {GeoHash: "9xj65hj9x5s5", StreetNum: 757, StreetName: "E 20th Ave", City: "Denver", State: "CO", ZIP: 80205})<-[:HAS]-(ad),
       (:Address {GeoHash: "9xj6501g49hz", StreetNum: 661, StreetName: "Logan St", City: "Denver", State: "CO", ZIP: 80203})<-[:HAS]-(ad),
       (:Address {GeoHash: "9xj64gcq9vjt", StreetNum: 1001 , StreetName: "16th St Mall", City: "Denver", State: "CO", ZIP: 80265})<-[:HAS]-(ad),
       (:Address {GeoHash: "9xj3dpfeuguu", StreetNum: 1957, StreetName: "S Federal Blvd", City: "Denver", State: "CO", ZIP: 80219})<-[:HAS]-(ad);   


// Booking #1 - Complete booking cycle containing Addresses that are not in our AddresseS collection.
// Steps: 1 - The Passenger Creates a Booking, 2 - a Car-Driver serves the Booking, 3 - the passenger is dropped at the Destinantion 

// 1 - Passenger Books a Ride: Create a Booking, Connect to Waiting -  create 1 Node, create 3 relationships in one Transaction 

// We check if the Origin GeoHash already exists in the AddresseS collection

MATCH (oa:Address {GeoHash: "9xj65189uetb"}) RETURN count(oa);

//IF it does not exist (count(oa) = 0), we Create an Address entry and connect it to the AddresseS collection

MATCH  (ad:AddresseS)
MERGE (:Address {GeoHash: "9xj65189uetb", StreetNum: 1180, StreetName: "Sherman St", City: "Denver", State: "CO", ZIP: 80203})<-[:HAS]-(ad);

// We check if the Destination GeoHash already exists in the AddresseS collection

MATCH (da:Address {GeoHash: "9xj65bnd6p9g"}) RETURN count(da);

//IF it does not exists (count(da) = 0), we Create an Address entry and connect it the AddresseS collection

MATCH  (ad:AddresseS)
MERGE (:Address {GeoHash: "9xj65bnd6p9g", StreetNum: 3728, StreetName: "E 7th Ave Pkwy", City: "Denver", State: "CO", ZIP: 80206})<-[:HAS]-(ad);

// 1 - We Create the Booking and connect it to both Origin and Destination Addresses and to a Payment Method. We then connect the Booking to the WaitinG collection - create 1 Node, create 6 relationships in one Transaction
// FYI - In our POC, for the Booking ID we will use the formula:  "B"+left(randomUUID(),8)+right(randomUUID(),4) , 
// and for the ride Fare, instead of calculating a real Fare, we will use the formula: ceil(rand()*20)+10" , to generate a random Fare.

OPTIONAL MATCH  (p:Passenger {Phone: "29837442"})-[:HAS_PREFERED_PAYMENT]-(pm), (w:WaitinG {Name: "WaitinG"}), (oa:Address {GeoHash: "9xj65189uetb"})<-[:HAS]-(:AddresseS)-[:HAS]->(da:Address {GeoHash: "9xj65bnd6p9g"})
CREATE (b:Booking {BookingID: "B09637f9d543c", Date: localdatetime.transaction(), Fare: ceil(rand()*20)+10 })-[:HAS_PASSENGER]->(p),
       (b)-[:HAS_PAYMENT]->(pm),
       (b)-[:HAS_ORIGIN]->(oa),
       (b)-[:HAS_DESTINATION]->(da),
       (p)-[:HAS_ACTIVE_BOOKING]->(b), 
       (w)-[:HAS]->(b);

// Find Bookings that are Waiting  

MATCH (w:WaitinG)-[:HAS]->(b:Booking)-[:HAS_PASSENGER]->(p:Passenger), (oa)<-[:HAS_ORIGIN]-(b)-[:HAS_DESTINATION]->(da)
RETURN  b.BookingID, p.Name, oa.StreetNum, oa.StreetName, da.StreetNum, da.StreetName, apoc.temporal.format(duration.between(b.Date,datetime()),'HH:mm:ss.SSS') as TimeWaiting , b.Fare 
ORDER BY b.Date;

// 2 - Driver selects a Waiting booking: Assigne Car to Booking, Remove Car from Available, Connect Car as Busy, Connect Booking as Active, and Remove Booking from Waiting  -  create 4 relationships, disconnect 2 relationships in one Transaction 

OPTIONAL MATCH (b:Booking {BookingID:"B09637f9d543c"})<-[r1:HAS]-(w:WaitinG)<-[:HAS]-()-[:HAS]->(a:ActivE),
       (d:Driver {ID:"S84765968N"})-[:HAS_CAR]->(c)<-[r2:HAS]-(:AvailablE)<-[:HAS]-()-[:HAS]->(u:BusY) 
DELETE r1, r2
CREATE (a)-[:HAS]->(b),
       (c)-[r:HAS_ACTIVE_BOOKING]->(b), 
       (b)-[t:HAS_CAR]->(c),
       (u)-[:HAS]->(c);



// 3 - Passenger is dropped at destination: Delete active_booking from Passenger and Car, Mark Booking as Past, Mark Car as Available - connect 4 Edges, disconnect 4 Edges in one Transaction 

 OPTIONAL MATCH (dh:HistorY)<-[:HAS_HISTORY]-(d:Driver {ID:"S84765968N"})-[:HAS_CAR]->(c)-[r1:HAS_ACTIVE_BOOKING]->(b)<-[r3:HAS]-(:ActivE)<-[:HAS]-(:BookingS)-[:HAS]->(t:PasT), 
                (a:AvailablE)<-[:HAS]-(:FleeT)-[:HAS]->(u:BusY)-[r2:HAS]->(c),(ph:HistorY)<-[:HAS_HISTORY]-(p:Passenger)-[r4:HAS_ACTIVE_BOOKING]->(b)
CREATE (t)-[:HAS {Date: datetime()}]->(b), 
      (a)-[:HAS]->(c), 
      (dh)-[:HAS {Date: datetime()}]->(b),
      (b)<-[:HAS {Date: datetime()}]-(ph) 
DELETE r1, r2, r3, r4;




// 4 - Passenger Rates the ride:

MATCH (p:Passenger {Phone: "29837442"})-[:HAS_HISTORY]->()-[:HAS]-(b:Booking {BookingID:"B09637f9d543c"}) 
CREATE (b)-[:HAS_RATING]->(r:Rating {Date: localdatetime.transaction(), Stars: 4, Comments: "Good ride, good navigaton, polite driver"});



// Booking #2, #3, #4 , #5 with addresses that are already in our AddresseS collection - We will leave them as Waiting for a Car to select 

// Create a Booking, Put in Waiting  in one Transaction 

OPTIONAL MATCH  (p:Passenger {Phone: "40985343"})-[:HAS_PREFERED_PAYMENT]-(pm), (w:WaitinG {Name: "WaitinG"}), (oa:Address {GeoHash: "9xj64gcq9vjt"})<-[:HAS]-(:AddresseS)-[:HAS]->(da:Address {GeoHash: "9xj3dpfeuguu"})
CREATE (b:Booking {BookingID: "B85518e3420c7", Date: localdatetime.transaction(), Fare: ceil(rand()*20)+10 })-[:HAS_PASSENGER]->(p),
       (b)-[:HAS_PAYMENT]->(pm),
       (b)-[:HAS_ORIGIN]->(oa),
       (b)-[:HAS_DESTINATION]->(da),
       (p)-[:HAS_ACTIVE_BOOKING]->(b), 
       (w)-[:HAS]->(b);

OPTIONAL MATCH  (p:Passenger {Phone: "56230987"})-[:HAS_PREFERED_PAYMENT]-(pm), (w:WaitinG {Name: "WaitinG"}), (oa:Address {GeoHash: "9xj3fuwsetzu"})<-[:HAS]-(:AddresseS)-[:HAS]->(da:Address {GeoHash: "9xj6508tghbr"})
CREATE (b:Booking {BookingID: "B22318cb24f70", Date: localdatetime.transaction(), Fare: ceil(rand()*20)+10 })-[:HAS_PASSENGER]->(p),
       (b)-[:HAS_PAYMENT]->(pm),
       (b)-[:HAS_ORIGIN]->(oa),
       (b)-[:HAS_DESTINATION]->(da),
       (p)-[:HAS_ACTIVE_BOOKING]->(b), 
       (w)-[:HAS]->(b);

OPTIONAL MATCH  (p:Passenger {Phone: "820042321"})-[:HAS_PREFERED_PAYMENT]-(pm), (w:WaitinG {Name: "WaitinG"}), (oa:Address {GeoHash: "9xj6juhv9401"})<-[:HAS]-(:AddresseS)-[:HAS]->(da:Address {GeoHash: "9xj3duugfzhy"})
CREATE (b:Booking {BookingID: "B60b8e871d140", Date: localdatetime.transaction(), Fare: ceil(rand()*20)+10 })-[:HAS_PASSENGER]->(p), 
       (b)-[:HAS_PAYMENT]->(pm),
       (b)-[:HAS_ORIGIN]->(oa),
       (b)-[:HAS_DESTINATION]->(da),
       (p)-[:HAS_ACTIVE_BOOKING]->(b), 
       (w)-[:HAS]->(b);

OPTIONAL MATCH  (p:Passenger {Phone: "94003822"})-[:HAS_PREFERED_PAYMENT]-(pm), (w:WaitinG {Name: "WaitinG"}), (oa:Address {GeoHash: "9xj70g6z1xry"})<-[:HAS]-(:AddresseS)-[:HAS]->(da:Address {GeoHash: "9xj6cvxyeen7"})
CREATE (b:Booking {BookingID: "B28096628141b", Date: localdatetime.transaction(), Fare: ceil(rand()*20)+10 })-[:HAS_PASSENGER]->(p),
       (b)-[:HAS_PAYMENT]->(pm),
       (b)-[:HAS_ORIGIN]->(oa),
       (b)-[:HAS_DESTINATION]->(da),
       (p)-[:HAS_ACTIVE_BOOKING]->(b), 
       (w)-[:HAS]->(b);

// Booking #6 - Active  - That is, this Booking will be picked up by a Car-Driver 

// Create a Booking ,  Put in Waiting  in one Transaction 

// Lookup Address in at AdressBook

MATCH (p:Passenger {Phone: "23456683"})-[:HAS_ADDRESS]->()-[:HAS]->(fa:FavAddress)-[IS_ADDRESS]->(a:Address) RETURN fa.Name, a.StreetNum,a.StreetName, a.City,a.ZIP ;


OPTIONAL MATCH  (p:Passenger {Phone: "23456683"})-[:HAS_PREFERED_PAYMENT]-(pm), (w:WaitinG {Name: "WaitinG"}), (oa:Address {GeoHash: "9xj3gen11ug3"})<-[:HAS]-(:AddresseS)-[:HAS]->(da:Address {GeoHash: "9xj64g7vxjtr"})
CREATE (b:Booking {BookingID: "Be0ad83f4eca1", Date: localdatetime.transaction() ,  Fare: ceil(rand()*20)+10 })-[:HAS_PASSENGER]->(p),
       (b)-[:HAS_PAYMENT]->(pm),
       (b)-[:HAS_ORIGIN]->(oa),
       (b)-[:HAS_DESTINATION]->(da),
       (p)-[:HAS_ACTIVE_BOOKING]->(b), 
       (w)-[:HAS]->(b);

// Find Bookings that are Waiting - Find Bookings that are in the WaitinG collection 

MATCH (w:WaitinG)-[:HAS]->(b:Booking)-[:HAS_PASSENGER]->(p:Passenger), (oa)<-[:HAS_ORIGIN]-(b)-[:HAS_DESTINATION]->(da)
RETURN  b.BookingID, p.Name, oa.StreetNum, oa.StreetName, da.StreetNum, da.StreetName,  apoc.temporal.format(duration.between(b.Date,datetime()),'HH:mm:ss.SSS') as TimeWaiting , b.Fare 
ORDER BY b.Date;

// Driver selects a Booking - Assigne Car to Booking, Remove Car from Available, Mark Car as Busy, Mark Booking as Active, and Remove Booking from Waiting in one Transaction 

OPTIONAL MATCH  (b:Booking {BookingID:"Be0ad83f4eca1"})<-[r1:HAS]-(w:WaitinG), 
       (c:Car {Plate: "ABC-1234"})<-[r2:HAS]-(:AvailablE), 
       (a:ActivE {Name: "ActivE"}), 
       (u:BusY {Name: "BusY"}) 
DELETE r1, r2
CREATE (a)-[:HAS]->(b),
       (c)-[r:HAS_ACTIVE_BOOKING]->(b), 
       (b)-[t:HAS_CAR]->(c),
       (u)-[:HAS]->(c);




// Other transactions:

// Mark Car as OffDuty 

MATCH (d:Driver {ID:"S18487473N"})-[:HAS_CAR]->(c)<-[r:HAS]-(a:AvailablE)-[]-(:FleeT)-[]-(o:OffDutY)
DELETE r 
CREATE (c)<-[:HAS {Date: datetime()}]-(o);

// Mark Car from Available to Maintenance 

MATCH (d:Driver {ID:"S98376432N"})-[:HAS_CAR]->(c)<-[r:HAS]-(a:AvailablE)-[]-(:FleeT)-[]-(m:MaintenancE)
DELETE r 
CREATE (c)<-[:HAS {Date: datetime()}]-(m);



// Mark Car as Retired 

MATCH (c:Car {Plate: "ABG-5678"})<-[r:HAS]-(a:AvailablE)-[]-(:FleeT)-[]-(e:RetireD)
DELETE r 
CREATE (c)<-[:HAS {Date: datetime()}]-(e); 
 

