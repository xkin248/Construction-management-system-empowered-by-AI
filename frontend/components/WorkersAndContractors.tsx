import React, { useState } from 'react';

interface Worker {
  id: string;
  name: string;
  role: string;
  rating: number;
  hoursLogged: number;
  tasksCompleted: number;
  skills: string[];
  status: 'On Site' | 'Off Site';
  avatar: string;
}

const WorkersAndContractors: React.FC = () => {
  const [selectedWorker, setSelectedWorker] = useState<Worker | null>(null);
  const [filterProject, setFilterProject] = useState('All Projects');
  const [filterStatus, setFilterStatus] = useState('All Status');

  const workers: Worker[] = [
    {
      id: '1',
      name: 'Ali Hassan',
      role: 'Structural Engineer',
      rating: 4.8,
      hoursLogged: 312,
      tasksCompleted: 28,
      skills: ['Steel Framing', 'Concrete Work', '+1'],
      status: 'On Site',
      avatar: 'AH'
    },
    {
      id: '2',
      name: 'Boon Chong Tan',
      role: 'Electrical Contractor',
      rating: 4.5,
      hoursLogged: 288,
      tasksCompleted: 22,
      skills: ['HV Wiring', 'Panel Installation', '+1'],
      status: 'On Site',
      avatar: 'BC'
    },
    {
      id: '3',
      name: 'Mohamad Farid',
      role: 'Plumber',
      rating: 4.2,
      hoursLogged: 245,
      tasksCompleted: 18,
      skills: ['Pipe Fitting', 'Drainage Systems', '+1'],
      status: 'Off Site',
      avatar: 'MF'
    },
    {
      id: '4',
      name: 'Rajesh Kumar',
      role: 'Scaffolding Specialist',
      rating: 4.7,
      hoursLogged: 330,
      tasksCompleted: 31,
      skills: ['Steel Scaffolding', 'Safety Nets', '+1'],
      status: 'On Site',
      avatar: 'RK'
    },
    {
      id: '5',
      name: 'Nurul Ain Zainudin',
      role: 'Site Supervisor',
      rating: 4.9,
      hoursLogged: 356,
      tasksCompleted: 42,
      skills: ['Project Coordination', 'Safety Inspection', '+1'],
      status: 'On Site',
      avatar: 'NA'
    },
    {
      id: '6',
      name: 'David Lim',
      role: 'Mason',
      rating: 4.0,
      hoursLogged: 198,
      tasksCompleted: 14,
      skills: ['Bricklaying', 'Plastering', '+1'],
      status: 'On Site',
      avatar: 'DL'
    }
  ];

  const getWorkerAvatarColor = (name: string) => {
    const colors = ['bg-orange-500', 'bg-blue-500', 'bg-purple-500', 'bg-green-500', 'bg-pink-500', 'bg-yellow-500'];
    return colors[Math.floor(Math.random() * colors.length)];
  };

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white border-b border-gray-200 px-8 py-6 flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Workers & Contractors</h1>
          <p className="text-gray-600 mt-1">12 registered workers across 4 projects</p>
        </div>
        <button className="bg-orange-500 text-white px-6 py-2 rounded-lg font-semibold hover:bg-orange-600">
          + Add Worker
        </button>
      </div>

      {/* Main Content */}
      <div className="p-8">
        {/* Summary Stats */}
        <div className="grid grid-cols-3 gap-6 mb-8">
          <div className="bg-white rounded-lg shadow p-6">
            <p className="text-gray-600 text-sm">On Site</p>
            <p className="text-4xl font-bold text-gray-900 mt-2">10</p>
            <p className="text-gray-600 text-xs mt-2">Active today</p>
          </div>
          <div className="bg-white rounded-lg shadow p-6">
            <p className="text-gray-600 text-sm">Off Site</p>
            <p className="text-4xl font-bold text-gray-900 mt-2">2</p>
            <p className="text-gray-600 text-xs mt-2">Not working</p>
          </div>
          <div className="bg-white rounded-lg shadow p-6">
            <p className="text-gray-600 text-sm">Avg Rating</p>
            <p className="text-4xl font-bold text-yellow-500 mt-2">4.5</p>
            <p className="text-gray-600 text-xs mt-2">Overall performance</p>
          </div>
        </div>

        {/* Workers Grid and Details */}
        <div className="grid grid-cols-2 gap-8">
          {/* Workers Grid */}
          <div className="col-span-1">
            {/* Search and Filters */}
            <div className="mb-6">
              <input
                type="text"
                placeholder="Search by name or role..."
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-500"
              />
            </div>

            <div className="flex gap-4 mb-6">
              <select
                value={filterProject}
                onChange={(e) => setFilterProject(e.target.value)}
                className="px-4 py-2 border border-gray-300 rounded-lg focus:outline-none"
              >
                <option>All Projects</option>
              </select>
              <select
                value={filterStatus}
                onChange={(e) => setFilterStatus(e.target.value)}
                className="px-4 py-2 border border-gray-300 rounded-lg focus:outline-none"
              >
                <option>All Status</option>
                <option>On Site</option>
                <option>Off Site</option>
              </select>
            </div>

            {/* Workers Cards */}
            <div className="grid grid-cols-2 gap-4">
              {workers.map((worker) => (
                <div
                  key={worker.id}
                  onClick={() => setSelectedWorker(worker)}
                  className={`border-2 rounded-lg p-4 cursor-pointer transition ${
                    selectedWorker?.id === worker.id
                      ? 'border-orange-500 bg-orange-50'
                      : 'border-gray-200 bg-white hover:border-gray-300'
                  }`}
                >
                  <div className="flex items-center gap-3 mb-3">
                    <div className={`w-12 h-12 rounded-full flex items-center justify-center text-white font-bold ${getWorkerAvatarColor(worker.name)}`}>
                      {worker.avatar}
                    </div>
                    <div className="flex-1">
                      <h3 className="font-bold text-gray-900 text-sm">{worker.name}</h3>
                      <p className="text-gray-600 text-xs">{worker.role}</p>
                    </div>
                    <div className={`w-2 h-2 rounded-full ${worker.status === 'On Site' ? 'bg-green-500' : 'bg-gray-400'}`}></div>
                  </div>
                  <div className="flex items-center gap-2 mb-2">
                    <div className="flex items-center gap-1">
                      <span className="text-yellow-500">⭐</span>
                      <span className="font-bold text-gray-900 text-sm">{worker.rating}</span>
                    </div>
                    <span className="text-gray-600 text-xs">{worker.hoursLogged}h logged</span>
                  </div>
                  <div className="flex gap-1 mb-3 flex-wrap">
                    {worker.skills.map((skill, idx) => (
                      <span key={idx} className="px-2 py-1 bg-gray-100 text-gray-700 rounded text-xs">
                        {skill}
                      </span>
                    ))}
                  </div>
                  <p className="text-gray-600 text-xs">{worker.tasksCompleted} tasks</p>
                </div>
              ))}
            </div>
          </div>

          {/* Worker Details Panel */}
          {selectedWorker && (
            <div className="col-span-1 bg-gray-900 text-white rounded-lg shadow p-6">
              {/* Worker Avatar and Basic Info */}
              <div className="text-center mb-6">
                <div className={`w-24 h-24 rounded-full flex items-center justify-center text-white font-bold text-3xl mx-auto mb-4 ${getWorkerAvatarColor(selectedWorker.name)}`}>
                  {selectedWorker.avatar}
                </div>
                <h2 className="text-2xl font-bold">{selectedWorker.name}</h2>
                <p className="text-gray-400 text-sm">{selectedWorker.role}</p>
                <div className="flex justify-center gap-1 mt-2">
                  {[...Array(5)].map((_, i) => (
                    <span key={i} className={i < Math.floor(selectedWorker.rating) ? 'text-yellow-500' : 'text-gray-600'}>⭐</span>
                  ))}
                  <span className="text-gray-400 text-sm ml-2">{selectedWorker.rating}</span>
                </div>
                <div className={`inline-block mt-2 px-3 py-1 rounded-full text-sm font-semibold ${
                  selectedWorker.status === 'On Site' ? 'bg-green-900 text-green-200' : 'bg-gray-700 text-gray-300'
                }`}>
                  • {selectedWorker.status}
                </div>
              </div>

              {/* Stats */}
              <div className="grid grid-cols-3 gap-4 mb-6 pb-6 border-b border-gray-700">
                <div className="text-center">
                  <p className="text-gray-400 text-sm">Hours</p>
                  <p className="text-2xl font-bold">{selectedWorker.hoursLogged}</p>
                </div>
                <div className="text-center">
                  <p className="text-gray-400 text-sm">Tasks</p>
                  <p className="text-2xl font-bold">{selectedWorker.tasksCompleted}</p>
                </div>
                <div className="text-center">
                  <p className="text-gray-400 text-sm">Rate/h</p>
                  <p className="text-2xl font-bold">RM45</p>
                </div>
              </div>

              {/* Contact Info */}
              <div className="mb-6 pb-6 border-b border-gray-700">
                <p className="text-gray-400 text-sm mb-2">📞 Contact</p>
                <p className="font-semibold">+60 12-345 6789</p>
              </div>

              {/* Current Project */}
              <div className="mb-6 pb-6 border-b border-gray-700">
                <p className="text-gray-400 text-sm mb-2">Current Project</p>
                <p className="font-semibold">🏗️ Kuala Lumpur Tower Block A</p>
              </div>

              {/* Skills */}
              <div className="mb-6 pb-6 border-b border-gray-700">
                <p className="text-gray-400 text-sm mb-3">Skills</p>
                <div className="flex gap-2 flex-wrap">
                  {selectedWorker.skills.map((skill, idx) => (
                    <span key={idx} className="px-3 py-1 bg-gray-700 rounded-lg text-sm">
                      {skill}
                    </span>
                  ))}
                </div>
              </div>

              {/* Certifications */}
              <div className="mb-6">
                <p className="text-gray-400 text-sm mb-3">Certifications</p>
                <div className="space-y-2">
                  <div className="flex items-center gap-2">
                    <span className="text-yellow-500">🏆</span>
                    <span className="text-sm">CIDB Green Card</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-yellow-500">🏆</span>
                    <span className="text-sm">Safety Officer</span>
                  </div>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="space-y-2">
                <button className="w-full bg-orange-500 text-white py-2 rounded-lg font-semibold hover:bg-orange-600">
                  Assign Task
                </button>
                <button className="w-full text-orange-500 border border-orange-500 py-2 rounded-lg font-semibold hover:bg-orange-50">
                  View Profile
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default WorkersAndContractors;