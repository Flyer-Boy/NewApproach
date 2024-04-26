

// ************* Some Cypher queries  ************* 

// Find all the Cars in the Fleet regardless of their state  (All elements of FleeT)

MATCH (:FleeT)-[:HAS]-{2}(c:Car) RETURN c;

// Find all the Bookings regardless of their state  (All elements of BookingS)

MATCH (:BookingS)-[:HAS]-{2}(b) RETURN b;



//Find all Cars in the Fleet that are near (~15Km Radius) to Geohash "9xj3f3yvo43o" (1298 S Raritan St, Denver, CO 80223, USA) - You should see 6 cars

MATCH (:FleeT)-[:HAS]-{2}(c:Car)-[:IS_AT]-(l:Loc) WHERE left(l.GeoHash, 4) = "9xj3" RETURN c ;

//For Push Bookings (System selects a Car that is near to Booking's origin) - Find all Availabe Cars in the Fleet that are near (~15Km Radius) to Geohash "9xj3f3yvo43o" (1298 S Raritan St, Denver, CO 80223, USA) - You should see 3 cars

MATCH (:AvailablE)-[:HAS]-(c:Car)-[:IS_AT]-(l:Loc) WHERE left(l.GeoHash, 4) = "9xj3" RETURN c ;

//For Push Bookings (System selects a Car that is near to Booking's origin) - Find all Availabe Cars in the Fleet that are closer (~2.7Km Radius) to Geohash "9xj3f3yvo43o" (1298 S Raritan St, Denver, CO 80223, USA) - You should see 2 cars

MATCH (:AvailablE)-[:HAS]-(c:Car)-[:IS_AT]-(l:Loc) WHERE left(l.GeoHash, 5) = "9xj3f" RETURN c ;



//For Pull Bookings (Driver selects a Booking that has an Origin near to them) - Find all Waiting Bookings near (~15Km Radius) GeoHash "9xj6" (Total database accesses: 29, total allocated memory: 64)

MATCH (:WaitinG)-[:HAS]-(b)-[:HAS_ORIGIN]-(a) WHERE left(a.GeoHash, 4) = "9xj6" RETURN b;

 // alternative (Total database accesses: 52, total allocated memory: 64)

MATCH (p:Passenger)-[:HAS_ACTIVE_BOOKING]->(b)-[:HAS_ORIGIN]->(a)
WHERE NOT (b)<-[:HAS_ACTIVE_BOOKING]-(:Car) AND left(a.GeoHash, 4) = "9xj6" RETURN b;



// Find all Elements of a Passenger 

MATCH (p:Passenger {Phone: "29837442"})-[r:HAS_ADDRESS|HAS_HISTORY|HAS_WALLET|HAS]->{1,4}(n)  RETURN p,n 
MATCH (p:Passenger {Phone: "23456683"})-[]->{1,5}(n) RETURN p,n




// Find Bookings that are in the WaitinG collection  (Total database accesses: 97, total allocated memory: 2680)

PROFILE MATCH (w:WaitinG)-[:HAS]->(b)-[:HAS_PASSENGER]->(p), (oa)<-[:HAS_ORIGIN]-(b)-[:HAS_DESTINATION]->(da)
RETURN  b.BookingID, p.Name, oa.StreetNum, oa.StreetName, da.StreetNum, da.StreetName, apoc.temporal.format(duration.between(b.Date,datetime()),'HH:mm:ss.SSS') as TimeWaiting , b.Fare 
ORDER BY b.Date;

// or Find Passenger ACTIVE_BOOKING that NOT ACTIVE_BOOKING for Cars  (Total database accesses: 92, total allocated memory: 2744)

PROFILE MATCH (p:Passenger)-[:HAS_ACTIVE_BOOKING]->(b), (oa)<-[:HAS_ORIGIN]-(b)-[:HAS_DESTINATION]->(da)
WHERE NOT (b)<-[:HAS_ACTIVE_BOOKING]-(:Car) 
RETURN  b.BookingID, p.Name, oa.StreetNum, oa.StreetName, da.StreetNum, da.StreetName, apoc.temporal.format(duration.between(b.Date,datetime()),'HH:mm:ss.SSS') as TimeWaiting , b.Fare 
ORDER BY b.Date;


// Cardinality of Available Cars

MATCH (c:Car)<-[:HAS]-(n:AvailablE) RETURN count (c) as Cars_Available 

// Cardinality of Waiting Bookings

MATCH (b:Booking)<-[:HAS]-(:WaitinG) RETURN count(b) AS Bookings_Waiting

// Compare the Cardinality of Available Cars vs. Bookings Waiting

MATCH (c:Car)<-[:HAS]-(:AvailablE)
CALL {MATCH (b:Booking)<-[:HAS]-(:WaitinG) RETURN count(b) AS Bookings_Waiting}
WITH Bookings_Waiting, count (c) as Cars_Available RETURN Cars_Available, Bookings_Waiting  




// CREATE a Customer with ShoppingCarT (empty), WalleT (2 cards) and AddressBooK (2 addresses) collections - Used in the Article

CREATE (c:Customer {FirstName: "John", LastName: "Connor" , DOB: "02051985", ID: 83773729322 ,Phone: "(303)2345683", Email: "JohnC@email.com" , Photo: "https://photos.com/img/JohnC.jpg"})-[:HAS_CART]->(:ShoppingCarT {Name: "ShoppingCarT"}), 
(c)-[:HAS_WALLET]->(w:HAS_WALLET {Name: "WalleT"})-[:HAS]->(:PaymentMethod {Type: "CreditCard", Issuer: "Amex", NameOnCard: "John Connor", CardNumber: 3742454554001263, ExpDate: "05/26", CVV: 9065}),
(w)-[:HAS]->(:PaymentMethod {Type: "DebitCard", Issuer: "Visa", NameOnCard: "John Connor", CardNumber: 4701322211111234, ExpDate: "12/26", CVV: 837}),
(c)-[:HAS_ADDRESS]->(ab:HAS_ADDRESSBooK {Name:"AddressBooK"})-[:HAS]->(:BillingAddress {Name: "Home" , StreetNum: 950, StreetName: "S Elizabeth St", Complement: "Suite #5", City: "Denver", State: "CO", ZIP: 80209}),
(ab)-[:HAS]->(:ShippingAddress {Name: "Work", StreetNum: 600, StreetName: "17th St", Complement: "Suite #5899", City: "Denver", State: "CO", ZIP: 80202});


