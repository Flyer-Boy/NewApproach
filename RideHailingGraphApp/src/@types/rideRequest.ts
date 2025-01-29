import { rideRequestSchema } from "@ride-hailing/schema/rideRequest";
import * as yup from "yup";

export type RideRequestSchemaType = yup.InferType<typeof rideRequestSchema>;
