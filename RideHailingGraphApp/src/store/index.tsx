import { PassengerStoreType } from "@ride-hailing/@types/store";
import { create } from "zustand";

export const useUserData = create<PassengerStoreType>()((set) => ({
  bookingId: "",
  stage: "",
  reload: true,
  rideCount: 0,

  setRideCount: (rideCount: number) =>
    set((state) => ({ ...state, rideCount: rideCount })),
  setReload: (reload: boolean) =>
    set((state) => ({ ...state, reload: reload })),
  setBookingId: (id: string) => set((state) => ({ ...state, bookingId: id })),
  setStage: (newStage: string) =>
    set((state) => ({ ...state, stage: newStage })),
}));
