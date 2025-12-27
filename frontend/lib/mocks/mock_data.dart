/// Mock Data for Speak2Fill Hackathon Project
/// 
/// Simulates backend responses containing:
/// 1. OCR Image Dimensions
/// 2. Form Fields with Bounding Boxes
/// 
/// This allows the frontend to be developed without a live backend.

class MockData {
  // Simulating the original form image dimensions (e.g. from a camera capture or scan)
  static const double imageWidth = 1200.0;
  static const double imageHeight = 1600.0;

  // Ordered list of fields to process
  static final List<Map<String, dynamic>> formFields = [
    {
      'id': 'name_field',
      'label': 'Name',
      'question': 'I will help you fill this form. What is your name?',
      'response': 'Please write your name in the highlighted box.',
      'bbox': [280.0, 200.0, 900.0, 280.0], // [x1, y1, x2, y2]
      'example': 'RAVI KUMAR',
    },
    {
      'id': 'dob_field',
      'label': 'Date of Birth',
      'question': 'Great! Now, what is your date of birth?',
      'response': 'Please write your date of birth in the highlighted box.',
      'bbox': [280.0, 350.0, 650.0, 430.0],
      'example': '15/08/1990',
    },
    {
      'id': 'phone_field',
      'label': 'Phone Number',
      'question': 'What is your phone number?',
      'response': 'Please write your phone number in the highlighted box.',
      'bbox': [280.0, 500.0, 700.0, 580.0],
      'example': '9876543210',
    },
    {
      'id': 'address_field',
      'label': 'Address',
      'question': 'What is your address?',
      'response': 'Please write your address in the highlighted box.',
      'bbox': [280.0, 650.0, 1000.0, 730.0],
      'example': '123 MAIN STREET, MUMBAI',
    },
  ];
}
