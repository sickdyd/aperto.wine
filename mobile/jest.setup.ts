// @testing-library/react-native ships its Jest matchers built in since v12.4;
// the old `extend-expect` entry point no longer exists.

// The app never reaches the network in tests. Anything that does is a bug in
// the test, not a slow test — mirroring the Rails suite, where WebMock is on.
jest.mock("axios");

jest.mock("expo-secure-store", () => ({
  getItemAsync: jest.fn(async () => null),
  setItemAsync: jest.fn(async () => undefined),
  deleteItemAsync: jest.fn(async () => undefined),
}));
