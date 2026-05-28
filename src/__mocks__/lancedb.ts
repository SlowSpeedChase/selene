export const connect = jest.fn().mockResolvedValue({
  tableNames: jest.fn().mockResolvedValue([]),
  openTable: jest.fn(),
  createTable: jest.fn(),
});
