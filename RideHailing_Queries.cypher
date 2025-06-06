

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

MATCH (p:Passenger {Phone: "29837442"})-[r:HAS_ADDRESS|HAS_HISTORY|HAS_WALLET|HAS]->{1,4}(n)  RETURN p,n, r
MATCH (p:Passenger {Phone: "23456683"})-[r]->{1,5}(n) RETURN p,n,r




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

// Compare the Cardinality of Available Cars vs. Bookings Waiting and use then to creat a dynamic Fare 

OPTIONAL MATCH (c:Car)<-[:HAS]-(:AvailablE)
CALL () {MATCH (b:Booking)<-[:HAS]-(:WaitinG) RETURN toFloat(count(b)) AS Bookings_Waiting}
WITH Bookings_Waiting, toFloat(count (c)+0.5) as Cars_Available RETURN round(toFloat(Bookings_Waiting/(Cars_Available))*ceil(rand()*25)+15,2) as Fare


// Booking Times Audit:

MATCH (:PasT)-[f:HAS]->(b:Booking )-[p:PICKED_UP]->(c:Car), (b)-[bt:HAS_CAR]-(c) 
RETURN b.BookingID, b.Date as Booked_Time, apoc.temporal.format(duration.between(b.Date,bt.Date),'HH:mm:ss') as Car_WaitingTime,
bt.Date as CarAssigned_Time, apoc.temporal.format(duration.between(bt.Date,p.Date),'HH:mm:ss') as PickUp_WaitingTime,
p.Date as PickUp_Time, apoc.temporal.format(duration.between(p.Date,f.Date),'HH:mm:ss') as RideTime,
f.Date as DropOff_Time 
ORDER BY b.Date DESC; 


// Comparison: 
// Retrieving the past Bookings from a Passenger using the Passenger's HistorY collection 

PROFILE MATCH (dr:Passenger {Phone: "83987809"})-[:HAS_HISTORY]->(h:HistorY)-[:HAS]->(b:Booking)-[:HAS_CAR]->(c)-[:HAS_DRIVER]-(d), (pickUp:Address)<-[:HAS_ORIGIN]-(b)-[:HAS_DESTINATION]->(dropOff:Address)
RETURN toString(b.Fare) as Fare, d.Name as Name, d.Photo as Photo, d.Phone as Phone, apoc.temporal.format(b.Date,'DD, MMM YYYY - HH:mm') as Date,
pickUp.StreetNum + " " + pickUp.StreetName + ", " + pickUp.City + ", " + pickUp.State + ", " + pickUp.ZIP  as pickUpName, 
dropOff.StreetNum + " " + dropOff.StreetName + ", " + dropOff.City + ", " + dropOff.State + ", " + dropOff.ZIP  as dropOffName ORDER BY b.Date DESC LIMIT 10


// Retrieving the past Bookings from a Passenger  without using the Passenger's HistorY collection 

PROFILE MATCH (dr:Passenger {Phone: "83987809"})<-[:HAS_PASSENGER]-(b:Booking)-[:HAS_CAR]->(c)-[:HAS_DRIVER]-(d), (pickUp:Address)<-[:HAS_ORIGIN]-(b)-[:HAS_DESTINATION]->(dropOff:Address)
RETURN toString(b.Fare) as Fare, d.Name as Name, d.Photo as Photo, d.Phone as Phone, apoc.temporal.format(b.Date,'DD, MMM YYYY - HH:mm') as Date,
pickUp.StreetNum + " " + pickUp.StreetName + ", " + pickUp.City + ", " + pickUp.State + ", " + pickUp.ZIP  as pickUpName, 
dropOff.StreetNum + " " + dropOff.StreetName + ", " + dropOff.City + ", " + dropOff.State + ", " + dropOff.ZIP  as dropOffName ORDER BY b.Date DESC LIMIT 10



