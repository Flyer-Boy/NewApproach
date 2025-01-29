import {
  FormControlProps,
  InputFieldProps,
  SelectFieldProps,
} from "@ride-hailing/@types/props";
import InputField from "./InputField";
import SelectField from "./SelectField";

const FormControl = ({ inputControl, ...rest }: FormControlProps) => {
  switch (inputControl) {
    case "input":
      return <InputField {...(rest as InputFieldProps)} />;

    case "select":
      return <SelectField {...(rest as SelectFieldProps)} />;

    default:
      return null;
  }
};

export default FormControl;
