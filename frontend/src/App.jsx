import { Routes, Route } from 'react-router-dom';
import { ChatPage } from './pages/ChatPage';
import { ConfigPage } from './pages/ConfigPage';

function App() {
  return (
    <Routes>
      <Route path="/" element={<ChatPage />} />
      <Route path="/config" element={<ConfigPage />} />
    </Routes>
  );
}

export default App;
