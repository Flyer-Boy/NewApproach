import * as yup from "yup";
import { stringRequired } from "./Common/string";

export const rideRequestSchema = yup.object({
  pickUpId: stringRequired("Pick up location"),
  dropOffId: stringRequired("Drop Off location"),
  paymentMethod: stringRequired("Payment method"),
});
