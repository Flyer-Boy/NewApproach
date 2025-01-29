import { InputProps, SelectProps } from "@chakra-ui/react";
import { ReactNode } from "react";
import { FieldError } from "react-hook-form";
import { InputControlTypes } from ".";

export type LayoutProps = {
  children: ReactNode;
  onlyNavbar?: boolean;
};

export type CustomLayoutProps = {
  element: ReactNode;
};

export type SidebarItemsProps = {
  name: string;
  icon: ReactNode;
  link: string;
};

export type TransactionCardTypes = {
  pickUp: string;
  dropOff: string;
  time: string;
  amount: string;
};

export type PreviousCardTypes = {
  passengerId?: number;
  rideId?: number;
  name: string;
  phoneNumber: string;
  pickUp: string;
  dropOff: string;
  photo: string;
  fare: string;
  date: string;
};

export type FormWrapperProps = {
  label?: string;
  labelSize?: string;
  children: React.ReactNode;
  error?: FieldError;
  isRequired?: boolean;
  showErrorMessage?: boolean;
};

export type FormControlProps = {
  inputControl: InputControlTypes;
} & (InputFieldProps | SelectFieldProps);

export type InputFieldProps = InputProps & {
  label: string;
  placeholder?: string;
  type?: string;
  name: string;
  maxLength?: number;
  inputLeftElement?: React.ReactNode;
  inputRightElement?: React.ReactNode;
  isRequired?: boolean;
  isReadOnly?: boolean;
  customError?: FieldError;
};
export type SelectFieldProps = SelectProps & {
  label: string;
  placeholder?: string;
  name: string;
  inputLeftElement?: React.ReactNode;
  inputRightElement?: React.ReactNode;
  isRequired?: boolean;
  isReadOnly?: boolean;
  customError?: FieldError;
  options: { id: string; Address: string }[];
};

export type DriverListProps = {
  Name: string;
  ID: string;
  Email: string;
  Phone: string;
  Photo: string;
  Status: string;
  License: string;
  Color: string;
  Make: string;
  Model: string;
  Plate: string;
  Capacity: string;
};

export type PassengerListProps = {
  Name: string;
  Email: string;
  Phone: string;
  Photo: string;
  Status: string;
};
