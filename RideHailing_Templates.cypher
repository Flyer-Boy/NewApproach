


// ****************  Passenger  App  *******************



// Check if the Passenger has an Active Booking:

MATCH (p:Passenger  {Phone: "<phone>"})-[:HAS_ACTIVE_BOOKING]->(b) RETURN count(*);

// If 0, there is no active booking; If 1, then has an Active Booking

//or

MATCH (p:Passenger {Phone:"<phone>"}) RETURN EXISTS((p)-[:HAS_ACTIVE_BOOKING]->()) AS recordExists

// If FALSE, there is no active booking; If TRUE, then has an Active Booking



//Passenger Particulars & Structure

MATCH (ps:PassengerS) 
CREATE  (ps)-[:HAS]->(p:Passenger {Name: "<Passenger Name>", Phone: "<phone>", Email: "<email address>" , Photo: "<URL provided by the microservice>"})-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), 
(p)-[:HAS_WALLET]->(w:WalleT {Name: "WalleT"}),
(p)-[:HAS_ADDRESS]->(ab:AddressBooK {Name:"AddressBooK"});



//Passenger Payment Methods (Anchor nodes: Passenger Phone)

MATCH  (p:Passenger { Phone: "<phone number>"})
CREATE (p)-[:HAS_WALLET]->(w:WalleT)-[:HAS]->(pm1:PaymentMethod {Type: "<type>", Issuer: "<issuer>", NameOnCard: "<name on card>", CardNumber: <card number>, ExpDate: "<exp. Date>", CVV: <CVV>}), 
(p)-[:HAS_PREFERED_PAYMENT]->(pm1);


//Passenger Address Book (Anchor nodes: Passenger Phone)

// We check if the GeoHash already exists in the AddresseS collection

MATCH (a:Address {GeoHash: "<GeoHash>"}) RETURN count(a);

// IF the GeoHAsh already exists (count(a) = 1), we connect it to the Passengers Address book entry using the Name provided by the Passenger  

MATCH (a:Address {GeoHash: "<GeoHash>"}), (p:Passenger {Phone: "<phone number>"} )-[:HAS_ADDRESS]->(ab:AddressBooK {Name:"AddressBooK"})
MERGE (ab)-[:HAS]->(:FavAddress {Name: "<Nickname>"})-[:IS_ADDRESS]->(a);

// ELSE if the GeoHash does not exist (count(a) = 0), we create a new GeoHash Node, connect it to the AddresseS collection and to the Passengers Address book entry using the Name provided by the Passenger

MATCH (p:Passenger {Phone: "<phone number>"} )-[:HAS_ADDRESS]->(ab:AddressBooK {Name:"AddressBooK"}), (ad:AddresseS)
MERGE (ab)-[:HAS]->(:FavAddress {Name: "<Nickname>"})-[:IS_ADDRESS]->(:Address {GeoHash: "<GeoHash>", StreetNum: <number>, StreetName: "<street name>", City: "<city name>", State: "<state>", ZIP: <zip code>})<-[:HAS]-(ad);


//Passenger Booking (Anchor nodes: Passenger Phone)

//  We Create the Booking and connect it to both Origin and Destination Addresses and to a Payment Method. We then connect the Booking to the WaitinG collection - create 1 Node, create 6 relationships in one Transaction

OPTIONAL MATCH  (p:Passenger {Phone: "<phone number>"})-[:HAS_PREFERED_PAYMENT]-(pm), (w:WaitinG {Name: "WaitinG"}), (oa:Address {GeoHash: "<GeoHash>"})<-[:HAS]-(:AddresseS)-[:HAS]->(da:Address {GeoHash: "<GeoHash>"})
CREATE (b:Booking {BookingID: "B"+left(randomUUID(),8)+right(randomUUID(),4), Date: localdatetime.transaction(), Fare: ceil(rand()*20)+10 })-[:HAS_PASSENGER]->(p),
       (b)-[:HAS_PAYMENT]->(pm),
       (b)-[:HAS_ORIGIN]->(oa),
       (b)-[:HAS_DESTINATION]->(da),
       (p)-[:HAS_ACTIVE_BOOKING]->(b), 
       (w)-[:HAS]->(b);


//Passenger Booking Rating (Anchor nodes: Passenger Phone + Booking ID selected)

// Passenger Rates the ride:

MATCH (p:Passenger {Phone: "<phone number>"})-[:HAS_HISTORY]->()-[:HAS]-(b:Booking {BookingID:"<BookingID>"}) 
CREATE (b)-[:HAS_RATING]->(r:Rating {Date: localdatetime.transaction(), Stars: <Rating>, Comments: "<Passenger comments>"});





// ****************  Driver  App  *******************

// Check if the Driver has an Active Booking:

MATCH (d:Driver  {ID: "<Driver ID>"})-[:HAS_CAR]->(c)-[:HAS_ACTIVE_BOOKING]->(b) RETURN count(*);

// If 0, there is no active booking; If 1, then has an Active Booking

//or

MATCH (d:Driver {ID: "<Driver ID>"}) RETURN EXISTS((d)-[:HAS_CAR]->(c)-[:HAS_ACTIVE_BOOKING]->(b)) AS recordExists

// If FALSE, there is no active booking; If TRUE, then has an Active Booking




//  Driver/Car Particulars & Structure

// Create a new Driver and structure

OPTIONAL MATCH (dc:DriverS {Name: "DriverS"})
CREATE  (d:Driver {Name: "<Driver Name>", ID: "<Driver ID>", License: "<Drivers License>", Phone: "<Driver Phone Number>", Email: "<driver email>" , Photo: "<URL of Driver's photo>" }),
(dc)-[:HAS]->(d), 
(d)-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), 
(d)-[:HAS_WALLET]->(w:WalleT {Name: "WalleT"}); 


// Create a Car and assigne (connect) it to the Driver - set current location  (Anchor nodes: Driver ID)

MATCH (d:Driver {ID:"<Driver's ID>"}), (p:PendinG {Name: "PendinG"})
CREATE (d)-[:HAS_CAR]->(c:Car { Plate: "<Car licence plate number> ", Make: "<Car make>", Model:"<Car model>", Year: <Car Year>, Capacity: <Car passenger capacity>, Color: "<Car color>"})-[:HAS_DRIVER]->(d),
(c)-[:IS_AT]->(:Loc {GeoHash: "<GeoHash>" , Time: localdatetime.transaction()}),
(p)-[:HAS]->(c);


// Create a new Credit Method and set it as Prefered (Anchor nodes: Driver ID)

MATCH (d:Driver {ID:"<Driver's ID>"})-[:HAS_WALLET]->(w:WalleT {Name: "WalleT"})
CREATE (w)-[:HAS]->(cm:CreditMethod {Type: "Bank Tranfer", AccName: "<Account Name>" , AccNumber: <account number>, SWIFT_BIC: "<SWIFT Code>"}),
(d)-[:HAS_PREFERED_CREDIT]->(cm);


// Or


// All of the abouve in one command:  Create one Driver structure with Wallet, History, and its respective Car with the initial Location (Loc) and connect the Driver to the Car and vice-versa. Place the Car in the Peding Collection

OPTIONAL MATCH (p:PendinG {Name: "PendinG"}), (dc:DriverS {Name: "DriverS"})
CREATE  (d:Driver {Name: "<Driver Name>", ID: "<Driver ID>", License: "<Drivers License>", Phone: "<Driver Phone Number>", Email: "<driver email>" , Photo: "<URL of Driver's photo>" })-[:HAS_CAR]->(c:Car { Plate: "<Car licence plate number> ", Make: "<Car make>", Model:"<Car model>", Year: <Car Year>, Capacity: <Car passenger capacity>, Color: "<Car color>"})-[:HAS_DRIVER]->(d), 
(dc)-[:HAS]->(d), 
(d)-[:HAS_HISTORY]->(:HistorY {Name: "HistorY"}), 
(d)-[:HAS_WALLET]->(w:WalleT {Name: "WalleT"})-[:HAS]->(cm1:CreditMethod {Type: "Bank Tranfer", AccName: "<Account Name>" , AccNumber: <account number>, SWIFT_BIC: "<SWIFT Code>"}),
(d)-[:HAS_PREFERED_CREDIT]->(cm1),
(c)-[:IS_AT]->(:Loc {GeoHash: "<GeoHash>" , Time: localdatetime.transaction()}),
(p)-[:HAS]->(c);

// Update Car Location (Anchor nodes: Driver ID)

// Cypher command to Updating a Car current location from time to time - The system will need a Microservice to generate the GeoHash of the current car location based on GPS Latitude and Longitude

MATCH (d:Driver {ID:"<Driver's ID>"})-[HAS_CAR]-()-[IS_AT]->(l:Loc)
SET l.GeoHash = "<GeoHash>", l.Time = datetime();



//For Push Bookings (System selects a Car that is near to Booking's origin) - Find all Availabe Cars in the Fleet that are near (~15Km Radius) to Geohash "9xj3f3yvo43o" (1298 S Raritan St, Denver, CO 80223, USA)
MATCH (:AvailablE)-[:HAS]-(c:Car)-[:IS_AT]-(l:Loc) WHERE left(l.GeoHash, 4) = "9xj3" RETURN c ;

//For Push Bookings (System selects a Car that is near to Booking's origin) - Find all Availabe Cars in the Fleet that are closer (~2.7Km Radius) to Geohash "9xj3f3yvo43o" (1298 S Raritan St, Denver, CO 80223, USA)
MATCH (:AvailablE)-[:HAS]-(c:Car)-[:IS_AT]-(l:Loc) WHERE left(l.GeoHash, 5) = "9xj3f" RETURN c ;

//For Pull Bookings (Driver selects a Booking that has an Origin near to them) - Find all Waiting Bookings near (~15Km Radius) GeoHash "9xj6"
MATCH (:WaitinG)-[:HAS]-(b)-[:HAS_ORIGIN]-(a) WHERE left(a.GeoHash, 4) = "9xj6" RETURN b;


// Driver Selects a Booking (Anchor nodes: Driver ID + BookingID selected)

// Driver selects a Waiting booking: Assigne Car to Booking, Remove Car from Available, Connect Car as Busy, Connect Booking as Active, and Remove Booking from Waiting  -  create 4 relationships, disconnect 2 relationships in one Transaction 

OPTIONAL MATCH (b:Booking {BookingID:"<Booking ID selected>"})<-[r1:HAS]-(w:WaitinG)<-[:HAS]-()-[:HAS]->(a:ActivE), 
(d:Driver {ID:"<Driver's ID>"})-[:HAS_CAR]->(c)<-[r2:HAS]-(:AvailablE)<-[:HAS]-()-[:HAS]->(u:BusY) 
DELETE r1, r2
CREATE (a)-[:HAS]->(b),
       (c)-[r:HAS_ACTIVE_BOOKING]->(b), 
       (b)-[t:HAS_CAR]->(c),
       (u)-[:HAS]->(c);


//Driver Drops the Passenger (Anchor node: Driver ID)

// Passenger is dropped at destination: Delete active_booking from Passenger and Car, Mark Booking as Past, Mark Car as Available - connect 4 Edges, disconnect 4 Edges in one Transaction 

 OPTIONAL MATCH (dh:HistorY)<-[:HAS_HISTORY]-(d:Driver {ID:"<Drivre's ID>"})-[:HAS_CAR]->(c)-[r1:HAS_ACTIVE_BOOKING]->(b)<-[r3:HAS]-(:ActivE)<-[:HAS]-(:BookingS)-[:HAS]->(t:PasT), 
                (a:AvailablE)<-[:HAS]-(:FleeT)-[:HAS]->(u:BusY)-[r2:HAS]->(c),(ph:HistorY)<-[:HAS_HISTORY]-(p:Passenger)-[r4:HAS_ACTIVE_BOOKING]->(b)
CREATE (t)-[:HAS {Date: datetime()}]->(b), 
      (a)-[:HAS]->(c), 
      (dh)-[:HAS {Date: datetime()}]->(b),
      (b)<-[:HAS {Date: datetime()}]-(ph) 
DELETE r1, r2, r3, r4;

//Mark a Car as OffDuty or Maintenance (Anchor node: Driver ID)

// Mark Car as OffDuty 

MATCH (d:Driver {ID:"<Driver's ID>"})-[:HAS_CAR]->(c)<-[r:HAS]-(a:AvailablE)-[]-(:FleeT)-[]-(o:OffDutY)
DELETE r 
CREATE (c)<-[:HAS {Date: datetime()}]-(o);

// Mark Car from Available to Maintenance 

MATCH (d:Driver {ID:"<Driver's ID>"})-[:HAS_CAR]->(c)<-[r:HAS]-(a:AvailablE)-[]-(:FleeT)-[]-(m:MaintenancE)
DELETE r 
CREATE (c)<-[:HAS {Date: datetime()}]-(m);




// ****************  Back office App  *******************

// Car/Driver due diligence (Back Office App)

// After validating a Car/Driver, we move them to the AvailablE collection so they can start receiving Booking requests and serving Passengers 

MATCH (c:Car { Plate: "<Car licence plate>"})<-[r1:HAS]-(p:PendinG {Name:"PendinG"}), (a:AvailablE {Name: "AvailablE"}) 
CREATE (c)<-[r2:HAS]-(a) 
DELETE r1; 

// If a Car does not pass de Due Diligence we disconnect it from the PendinG collection and connect it to the RejecteD collection for the record/auditing 

MATCH (c:Car {Plate: "<Car licence plate>"})<-[r1:HAS]-(p:PendinG {Name:"PendinG"}), (j:RejecteD {Name: "RejecteD"}) 
CREATE (c)<-[r2:HAS]-(j) 
DELETE r1;

// Removing a Car from the Fleet

// Mark Car as Retired 

MATCH (c:Car {Plate: "<Car licence plate>"})<-[r:HAS]-(a:AvailablE)-[]-(:FleeT)-[]-(e:RetireD)
DELETE r 
CREATE (c)<-[:HAS {Date: datetime()}]-(e);
