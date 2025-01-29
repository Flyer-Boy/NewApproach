import { FieldError, useFormContext } from "react-hook-form";
import {
  Input,
  InputGroup,
  InputLeftElement,
  InputRightElement,
} from "@chakra-ui/react";
import FormWrapper from "./FormWrapper";
import { InputFieldProps } from "@ride-hailing/@types/props";

const InputField = ({
  label,
  placeholder,
  type,
  name,
  maxLength,
  customError,
  isRequired,
  inputLeftElement,
  inputRightElement,
  isReadOnly,
  ...rest
}: InputFieldProps) => {
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

        <Input
          {...register(name)}
          type={type ?? "text"}
          {...rest}
          maxLength={maxLength ? maxLength : undefined}
          placeholder={placeholder ? placeholder : `Enter ${label}`}
          onWheel={() => {
            if (type === "number") {
              (document.activeElement as HTMLElement).blur();
            }
          }}
          isReadOnly={isReadOnly ?? false}
          border={"1px solid"}
          borderColor={error ? "danger.300" : "gray.lighter"}
          _focus={{ borderColor: "primary.500" }}
          _disabled={{ borderColor: "gray.lighter", background: "#f2f2f2" }}
          height={"44px"}
        />

        {inputRightElement && (
          <InputRightElement top={"50%"} transform={"translateY(-50%)"}>
            {inputRightElement}
          </InputRightElement>
        )}
      </InputGroup>
    </FormWrapper>
  );
};

export default InputField;
