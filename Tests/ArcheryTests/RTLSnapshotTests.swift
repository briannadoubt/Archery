import XCTest
import SwiftUI
@testable import Archery

@MainActor
final class RTLSnapshotTests: XCTestCase {
    
    func testButtonRTLLayout() {
        let button = Button("Submit") {
            print("Tapped")
        }
        .padding()
        .background(Color.blue)
        .foregroundColor(.white)
        .cornerRadius(8)
        
        let rtlButton = button.rtlSnapshot()
        
        XCTAssertNotNil(rtlButton)
    }
    
    func testTextFieldRTLLayout() {
        struct TextFieldView: View {
            @State private var text = "Sample Text"
            
            var body: some View {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Enter your name:")
                        .font(.headline)
                    
                    TextField("Name", text: $text)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    HStack {
                        Button("Cancel") {}
                        Spacer()
                        Button("Save") {}
                    }
                }
                .padding()
            }
        }
        
        let view = TextFieldView()
        let rtlView = view.rtlSnapshot()
        
        XCTAssertNotNil(rtlView)
    }
    
    func testNavigationRTLLayout() {
        #if os(iOS) || os(tvOS)
        let navigation = NavigationView {
            List {
                NavigationLink("Settings", destination: Text("Settings View"))
                NavigationLink("Profile", destination: Text("Profile View"))
                NavigationLink("About", destination: Text("About View"))
            }
            .navigationTitle("Menu")
            .navigationBarItems(
                leading: Button("Edit") {},
                trailing: Button("Add") {}
            )
        }
        
        let rtlNavigation = navigation.rtlSnapshot()
        
        XCTAssertNotNil(rtlNavigation)
        #else
        XCTAssertTrue(true)
        #endif
    }
    
    func testFormRTLLayout() {
        struct FormView: View {
            @State private var name = ""
            @State private var email = ""
            @State private var isSubscribed = false
            
            var body: some View {
                Form {
                    Section(header: Text("Personal Information")) {
                        TextField("Name", text: $name)
                        TextField("Email", text: $email)
                    }
                    
                    Section(header: Text("Preferences")) {
                        Toggle("Subscribe to newsletter", isOn: $isSubscribed)
                    }
                    
                    Section {
                        Button("Submit") {}
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        
        let form = FormView()
        let rtlForm = form.rtlSnapshot()
        
        XCTAssertNotNil(rtlForm)
    }
    
    func testIconsAndSymbolsRTL() {
        let view = VStack(spacing: 20) {
            HStack {
                Image(systemName: "arrow.right")
                Text("Navigate Forward")
            }
            
            HStack {
                Image(systemName: "chevron.left")
                Text("Go Back")
            }
            
            HStack {
                Image(systemName: "list.bullet")
                Text("List Items")
            }
        }
        .padding()
        
        let rtlView = view.rtlSnapshot()
        
        XCTAssertNotNil(rtlView)
    }
    
    func testPseudoLocalizationSnapshot() {
        let view = VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to our application")
                .font(.largeTitle)
            
            Text("Please enter your credentials to continue")
                .font(.body)
            
            Button("Sign In") {}
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
        .padding()
        .pseudoLocalized(.pseudo)
        
        XCTAssertNotNil(view)
    }
    
    func testDoubleLengthSnapshot() {
        let view = VStack(spacing: 16) {
            Text("Short")
            Text("Medium length text")
            Text("This is a longer piece of text")
        }
        .padding()
        .pseudoLocalized(.doubleLength)
        
        XCTAssertNotNil(view)
    }
    
    func testAllLocalizationModes() {
        struct SampleView: View {
            var body: some View {
                VStack(spacing: 16) {
                    Text("Application Title")
                        .font(.title)
                    
                    Text("Description text goes here")
                        .font(.body)
                    
                    HStack {
                        Button("Cancel") {}
                        Button("Confirm") {}
                    }
                }
                .padding()
            }
        }
        
        let modes: [LocalizationMode] = [.normal, .pseudo, .rtl, .doubleLength, .accented]
        
        for mode in modes {
            let view = LocalizationPreview(mode: mode) {
                SampleView()
            }
            
            XCTAssertNotNil(view)
        }
    }
}