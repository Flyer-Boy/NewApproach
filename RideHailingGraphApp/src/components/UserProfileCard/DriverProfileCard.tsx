import { Center } from "@chakra-ui/react";
import UserProfileCard from ".";
import { useReadCypher } from "use-neo4j";
import CustomSpinner from "../Spinner";

const DriverProfileCard = () => {
  const userTypeId = localStorage.getItem("userTypeId");

  const query = `MATCH (d:Driver {ID: $id}) RETURN d`;

  const { records, loading } = useReadCypher(query, {
    id: userTypeId,
  });

  if (loading) {
    return (
      <Center h={"100%"}>
        <CustomSpinner />
      </Center>
    );
  }

  const data = records?.[0]?.get("d").properties;

  return <UserProfileCard data={data} />;
};

export default DriverProfileCard;
