import FormWrapper from "./FormWrapper";
import {
  InputGroup,
  InputLeftElement,
  InputRightElement,
  Select,
} from "@chakra-ui/react";
import { FieldError, useFormContext } from "react-hook-form";
import { SelectFieldProps } from "@ride-hailing/@types/props";

const SelectField = ({
  name,
  label,
  placeholder,
  customError,
  inputLeftElement,
  inputRightElement,
  isRequired,
  options,
  ...rest
}: SelectFieldProps) => {
  const {
    register,
    formState: { errors },
  } = useFormContext();

  const error = customError ?? (errors[name] as FieldError);
  return (
    <FormWrapper error={error} isRequired={isRequired} label={label}>
      <InputGroup
        position="relative"
        borderRadius={"12px"}
        border={"1px solid"}
        borderColor={error ? "danger.300" : "gray.lighter"}
      >
        {inputLeftElement && (
          <InputLeftElement>{inputLeftElement}</InputLeftElement>
        )}

        <Select
          {...register(name)}
          {...rest}
          placeholder={placeholder ? placeholder : `Enter ${label}`}
          border={"1px solid"}
          borderColor={error ? "danger.300" : "gray.lighter"}
          _focus={{ borderColor: "primary.500" }}
          _disabled={{ borderColor: "gray.lighter", background: "#f2f2f2" }}
          height={"44px"}
        >
          {options?.map((item) => (
            <option value={item.id} key={item.Address}>
              {item.Address}
            </option>
          ))}
        </Select>

        {inputRightElement && (
          <InputRightElement top={"50%"} transform={"translateY(-50%)"}>
            {inputRightElement}
          </InputRightElement>
        )}
      </InputGroup>
    </FormWrapper>
  );
};

export default SelectField;
