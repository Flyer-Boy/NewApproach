import * as yup from "yup";

export const stringRequired = (message: string) => {
  return yup.string().trim().required(`${message} is required.`);
};

export const stringNotRequired = () => {
  return yup.string().trim();
};
